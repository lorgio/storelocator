=begin
store.rb
Copyright 2009 wollzelle GmbH (http://wollzelle.com). All rights reserved.
=end

class StorelocatorStore < Storelocator::Base
  set_table_name "stores"

  BOM = "\377\376" #Byte Order Mark for excel
  GEO_PRECISION = 8
  
  #address configuration for template
  ADDRESS_SETTINGS = {}

  acts_as_wz_translateable :table_name => 'store_translations', :foreign_key => 'store_id'
  acts_as_wz_publishable :override_all_method => false, :uses_soft_delete => true, :revisioning => false

  acts_as_mappable  :default_units => :kms,
  :default_formular => :sphere,
  :distance_field_name => :distance,
  :lat_column_name => :lat,
  :lng_column_name => :lng,
  :auto_geocode => false

  belongs_to :city,       :class_name => 'StorelocatorCity'
  belongs_to :country,    :class_name => 'StorelocatorCountry'

  UPDATEABLE_FIELDS = [:name, :region_id, :country_id, :city_id, :state, :zip_code, :street, :additional, :phonenumber, :email, :lng, :lat, :shoptype_id, :accuracy]
  SHOPTYPES         = ['DOS', 'Retailer', 'Gucci duty free', 'Duty free retailer', 'Gucci flagship']
  SHOPTYPES_LABEL   = ['boutique', 'retailer', 'gucci duty free', 'duty free retailer', 'gucci flagship']
  ALLOWED_UNITS     = ["miles","kms"]
  GUCCI_STORETYPES  = [0,4]
  GUCCI_FLAGSHIP    = 4

  validates_presence_of  :name, :message => "Name can't be blank"
  validates_presence_of  :city_name, :message => "City name can't be blank"
  validates_presence_of  :street, :message => "Street can't be blank"
  validates_presence_of  :country_id, :message => "Country can't be blank"
  validates_presence_of  :city_id, :message => "City can't be blank"
  validates_presence_of  :shoptype_id, :message => "Shoptype can't be blank"
  validates_inclusion_of :shoptype_id, :in => Array(0..SHOPTYPES.length-1)

  named_scope :in_country, lambda {|country| 
      id = country.id rescue -1
      {:conditions => {:country_id => id} } } 
  named_scope :valid_location, :conditions => ['stores.lat+stores.lng is not null and stores.accuracy >= :acc', {:acc => GEO_PRECISION}]
  named_scope :missing_location, :conditions => 'lat is null or lng is null'
  named_scope :gucci, :conditions => 'shoptype_id in (0,4)'
  named_scope :retail, :conditions => 'shoptype_id = 1'
  named_scope :dutyfree, :conditions => 'shoptype_id in (2,3)'
  named_scope :without_retail, :conditions => 'shoptype_id != 1'

  named_scope :export_latin, :joins => [:city, :country], :conditions => 'stores.lang_link_id is null',  :select => 'stores.id as store_id, stores.name as latin_store_name,countries.printable_name as latin_country,countries.country_code as latin_country_code,cities.lng+cities.lat as city_coord, cities.printable_name as latin_city,state as latin_state,zip_code as latin_zip_code,street as latin_street,additional as latin_additional,shoptype_id,phonenumber as phone_number,email,accuracy'
  named_scope :export_local, lambda {|mainlanguage_id| {
    :conditions => ['stores.lang_link_id=:id',{:id => mainlanguage_id}], :joins => [:city, :country], :select => 'stores.name as local_storename,countries.printable_name as local_country,countries.country_code as local_country_code,cities.printable_name as local_city,state as local_state,zip_code as local_zip_code,street as local_street,additional as local_additional'}
  }

  named_scope :for_region, lambda {|region_id| {:conditions => ["region_id = :region", {:region => region_id} ] } }

  before_publish :check_before_publish
  before_save :check_city


  def check_city
    city = StorelocatorCity.first(:all, :conditions => ["country_id = :country_id and name = :name", {:country_id => self.country_id, :name => self.city_name}])

    begin
      if city.nil? then
        create_missing_city 
      else
        self.city = city
      end
    rescue 
      return false
    end
    true
  end

  def city_translation_modified?
    changed_translation = self.translations.detect { |trans| 
      city_trans =  self.city.translations.detect {|entry| entry.language == trans.language}
      city_trans.nil? || (city_trans.printable_name != trans.city_name)
      }
    (!changed_translation.nil?)
  end

  def create_missing_city 
    pname = StorelocatorCity.named_stripped(self.city_name)
    city = StorelocatorCity.create!(:country_id => self.country.id, :name => self.city_name, :printable_name => pname, :language => StorelocatorCity.default_language)
    # create default city
    ActiveRecord::Acts::WzTranslateable.configuration[:SITE_LANGUAGES].each do |lang|
      if lang != city.language then
        store_translation = self.translations.detect {|entry| entry.language == lang}
        if store_translation then
          city.translations << StorelocatorCity::Translation.create!(:language => lang, :printable_name => StorelocatorCity.named_stripped(store_translation.city_name)) # add additional lang
        else
          city.translations << StorelocatorCity::Translation.create!(:language => lang, :printable_name => pname) # add additional default lang
        end
      end
    end
    self.city = city
  end

  def update_city
    city = self.city
    self.translations.each do |trans| 
      if trans.language != city.language then # not default language
        city_trans = self.city.translations.detect {|entry| entry.language == trans.language}
        if (city_trans) then
          city_trans.printable_name = StorelocatorCity.named_stripped(trans.city_name)
          city_trans.save!
        else
          city.translations << StorelocatorCity::Translation.create!(:language => lang, :printable_name => StorelocatorCity.named_stripped(trans.city_name))
        end
      end
    end
  end

  def check_before_publish
    missing_translation  = translations.detect {|trans| trans.name.blank? || trans.street.blank?  }
    self.errors.add(:translations, "For all translations name and street are required") if missing_translation
    missing_translation.nil?
  end

  # get shoptypes as array 
  def self.shoptypes
    SHOPTYPES.collect {|name| [name, SHOPTYPES.index(name)]}
  end

  def self.find_exclusive(id)
    Store.with_exclusive_scope{find(id)}
  end

  def accurate?
    (self.accuracy || 0) >= GEO_PRECISION
  end

  def formal_name
    'store_' + self.name.parameterize.to_s.underscore
  end

  def self.shoptype(storetype_id)
    SHOPTYPES[storetype_id].downcase
  end

  def shoptype
    SHOPTYPES[self.storetype_id].downcase
  end

  def storeinfo_string
    return "#{self.name}, #{self.street}, #{self.city.name} #{self.zip_code}, #{self.country.country_code}"
  end

  def address_string
    return "#{self.street}, #{self.city.name} #{self.zip_code}, #{self.country.country_code}"
  end

  def update_location
    self.lng = nil
    self.lat = nil

    if self.assign_location and self.lng then
      self.save!
    else
      p "location not found: #{self.street}, #{self.city.name if self.city}, #{self.country.name}"
    end 
  end

  def accuracy_info
    case self.accuracy
    when nil,0: "No location" 
    when 1..4:  "Very poor (#{accuracy})"
    when 5..7:  "Poor (#{accuracy})"
    when 8..10: "Good (#{accuracy})"
    when 99:    "Manually set"
    end
  end

  def geo_manualset?
    return (self.accuracy == 99)
  end

  # location work better with country codes on googlemaps
  def assign_location
    if (self.lng.nil? || self.lat.nil?) && (self.street && self.city && self.country) then
      geoloc = Geokit::GeoLoc.new
      geoloc.country = self.country.name
      geoloc.country_code = self.country.country_code
      geoloc.city = self.city.name
      geoloc.zip = self.zip_code
      geoloc.street_address = self.street
      geoloc.state = self.state

      location = Storelocator::Location.geocode(geoloc, self.country)
      self.lng = location.lng
      self.lat = location.lat
      self.accuracy = location.accuracy
    end
  end

end
