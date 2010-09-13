=begin
storelocator.rb
Copyright 2010 wollzelle GmbH (http://wollzelle.com). All rights reserved.
=end

require 'active_record' 

module Storelocator
  module Settings
    class << self
      attr_accessor :configuration
    end
  end

  module Location
    class << self
      def geocode(address, country = nil, maxretries = 2)
        retries = 0
        country_added = FALSE
        ops = {}
        ops[:bais] = country.country_code if country
        ops[:bais] ||= address.country_code if address.is_a?(Geokit::GeoLoc)

        address_str = address.is_a?(Geokit::GeoLoc) ? address.to_geocodeable_s : address
        begin
          sleep 1 + 0.2*retries if (retries > 0)
          location = Geokit::Geocoders::MultiGeocoder.geocode(address_str, ops) rescue nil

          retries += 1
          wrong_result = (location.country_code.upcase != country.country_code.upcase) rescue false
          if !country_added && wrong_result then
            address_str = "#{address_str}, #{country.name}"
            location = nil
            country_added = TRUE
          end
        end while ((location.nil?) or (!location.success)) and (retries < maxretries)  
        location
      end

      def translate_address(country_code, address, language)
        # we do not want to have country code in result string
        address.country_code = nil if address.is_a?(Geokit::GeoLoc)
        address_str = address.is_a?(Geokit::GeoLoc) ? address.to_geocodeable_s : address

        retries = 0
        begin
          sleep 1 + 0.5*retries if (retries>0)
          res = Net::HTTP.get_response(URI.parse("http://maps.google.com/maps/geo?q=" + Geokit::Inflector::url_escape(address_str) + "&bais=#{country_code}&output=json&hl=#{language}"))
          p ("http://maps.google.com/maps/geo?q=" + Geokit::Inflector::url_escape(address_str) + "&bais=#{country_code}&output=json&hl=#{language}")
          json = JSON.parse(res.body) rescue nil
          code = json["Status"]["code"] rescue 0
          retries += 1
        end while (![200,602,620].index(code)) and (retries < 3)  
        [(code == 200) ? json : nil, code]
      end

      def translate_text(text, from_language, to_language)
        response, body = Net::HTTP.new('ajax.googleapis.com').post('/ajax/services/language/translate',"v=1.0&langpair=#{from_language}|#{to_language}&q=#{text}")
        json = JSON.parse(body)
        code = json["responseStatus"] rescue 0
        [(code == 200) ? json : nil, code]
      end

      def translate_region(region, options = {})
        status = 200
        from_language = options[:from_language] || DEFAULT_LANGUAGE
        langs = options[:to_languages] || MultiLanguage::TRANSLATE_LOCATIONS || MultiLanguage::DEFAULT_LANGUAGES

        res = langs.collect do |lang|
          translation, status = self.translate_text(region, from_language, lang) # rescue p "No translation for #{region} in #{lang}"
          return [nil, 620] if (status == 620) # blocked

          text = translation.scan_for_key('translatedText') rescue nil
          {:name => text.mb_chars.upcase.wrapped_string, :printable_name => text.mb_chars.capitalize.wrapped_string, :language => lang} rescue nil 
        end.compact

        p "FAILED: translation #{region}" if res.size!=langs.size
        [(status == 200) && (res.size == langs.size) ? res : nil, status]
      end

      def translate_country(country_code, country, options = {})
        retries = 0
        from_language = options[:from_language] || DEFAULT_LANGUAGE
        langs = options[:to_languages] || MultiLanguage::TRANSLATE_LOCATIONS || MultiLanguage::DEFAULT_LANGUAGES
        status = 200
        res = langs.collect do |lang|
          translation, status = self.translate_address(country_code, country, lang)
          return [nil, status] if (status == 620) or (status == 602) # blocked or wrong

          if translation then
            text = translation.scan_for_key('CountryName') rescue nil
          end

          if translation.nil? || (text.nil?) then
            translation, status = translate_text(country, from_language, lang) rescue nil
            return [nil, status] if (status == 620) or (status == 602) # blocked or wrong

            text = translation.scan_for_key('translatedText') rescue nil
          end

          {:name => text.mb_chars.upcase.wrapped_string, :printable_name => text.mb_chars.capitalize.wrapped_string, :language => lang} unless text.nil?
        end.compact

        p "FAILED: translation #{country}" if res.size!=langs.size
        [(status == 200) && (res.size == langs.size) ? res : nil, status]
      end

      def translate_city(country, city, options = {})
        zip_code = options[:zip_code]
        from_language = options[:from_language] || DEFAULT_LANGUAGE
        langs = options[:to_languages] || TRANSLATE_LOCATIONS || MultiLanguage::DEFAULT_LANGUAGES
        status = 200
        coordinates = nil

        geoloc = Geokit::GeoLoc.new
        geoloc.country = country.name
        geoloc.country_code = country.country_code
        geoloc.city = city

        res = langs.collect do |lang|
          translation, status = self.translate_address(country.country_code, geoloc, lang)
          return [nil, status] if (status == 620) or (status == 602) # blocked or wrong

          #p "translate city (#{status}): " + (zip_code.nil? ? "#{city}, #{country}" : "#{country}, #{zip_code} #{city}")
          if translation then
            #p "Translation: #{translation.inspect}"
            text = translation.scan_for_key('DependentLocalityName').mb_chars.strip.wrapped_string rescue nil
            text ||= translation.scan_for_key('LocalityName').mb_chars.strip.wrapped_string rescue nil
            text ||= translation.scan_for_key('name').mb_chars.strip.wrapped_string rescue nil
            coordinates = translation.scan_for_key('Point')['coordinates'] rescue nil

            # remove invalid translations 
            text = nil if (translation.scan_for_key('CountryNameCode') || country.country_code) != country.country_code  # was not valid
          end

          if translation.nil? || (text.nil?) then
            translation, status = translate_text(city, from_language, lang)
            return [nil, status] if (status == 620) or (status == 602) # blocked or address wrong

            text =  translation.scan_for_key('translatedText') rescue nil
          end

          {:name => text.mb_chars.upcase.wrapped_string, :printable_name => text.mb_chars.capitalize.wrapped_string, :language => lang} unless text.nil?
        end.compact

        p "FAILED: translation #{city} #{zip_code}" if res.size!=langs.size
        [(status == 200) && (res.size == langs.size) ? res : nil, status, coordinates]
      end

      # Verifies the location of cities based on the bounding box of the assigned country
      def verify_city_location
        Country.all(:conditions => "language='en'").each do |country|
          location = MultiLanguage::Location.geocode(country.name)
          bounds = location.suggested_bounds

          City.with_location.all(:conditions => ['language=:lang and country_id=:country', {:lang => 'en', :country => country.id}]).each do |city|
            if City.find_within_bounds(bounds, :conditions => {:id => city.id}).count > 0 then
              #p "#{city.name} - OK"
            else
              p "#{city.id} - #{city.name} - FAILED"
            end
          end
        end
      end
    end
  end
  
  # Base Class for Storelocator Modules
  class Base < ActiveRecord::Base
    self.abstract_class = true

    def self.database_configuration
      Storelocator::Settings.configuration['database'][ENV['RAILS_ENV']]
    end

    private 
    # get and set database connection based on YAML config file
    def self.initialize_connection
      # load in YAML configuration file 
      if defined?(Rails) then
        config_file = "#{Rails.root}/config/storelocator.yml"
        raise LoadError, "No storelocator config file found, make sure file #{config_file} exists, and the configuration is correct" unless File.exists?(config_file)

        Storelocator::Settings.configuration ||=  YAML.load_file(config_file)
        raise Error, "No database entry specified within configuration file #{config_file}!" unless Storelocator::Settings.configuration['database']

        establish_connection database_configuration
      end
    end
    
    self.initialize_connection
  end
  
  class Migration < ActiveRecord::Migration
    # use storelocator connection
    def self.connection
      Storelocator::Base.connection
    end
  end
end
