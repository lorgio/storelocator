=begin
storelocator_country.rb
Copyright 2009 wollzelle GmbH (http://wollzelle.com). All rights reserved.
=end

class StorelocatorCountry < Storelocator::Base
  set_table_name "countries"

  belongs_to :region,     :class_name => 'StorelocatorRegion' 
  belongs_to :capitalcity,:class_name => 'StorelocatorCity' 
  has_many   :stores,     :class_name => 'StorelocatorStore', :foreign_key => 'country_id'
  has_many   :cities,     :class_name => 'StorelocatorCity', :foreign_key => 'country_id', :dependent => :delete_all

  acts_as_wz_translateable :table_name => 'country_translations', :foreign_key => 'country_id'
  acts_as_wz_publishable :override_all_method => false, :uses_soft_delete => true, :revisioning => false
    
  validates_presence_of :printable_name, :message => "City name can't be blank."
  validates_presence_of :country_code, :message => "Country code can't be blank."
  validates_presence_of :iso3, :message => "Country code (iso3) can't be blank."
  validates_uniqueness_of :printable_name, :message => "A country with the same name already exists."                  
  validates_uniqueness_of :country_code, :message => "A country with the same country code already exists."                  
  validates_uniqueness_of :iso3, :message => "A country with the same country code(iso3) already exists."                  
  
  named_scope :in_region, lambda {|region| {:conditions => {:region_id => region.id} } } 
  named_scope :storecount, lambda { 
                lang = self.get_current_language
                {
                :select => "countries.id, countries.country_code, (select count(*) from stores where country_id =countries.id and publish_state='published') as store_count, countries.lng, countries.lat, cities.printable_name as capital_name, cities.lat as capital_lat, cities.lng as capital_lng", 
                :joins => [:capitalcity],
                :conditions => "(select count(*) from stores where country_id = countries.id and publish_state='published')>0"} }

  before_destroy :can_destroy
  before_save :set_default_values

  before_publish :check_before_publish

  def check_before_publish
    self.errors.add(:capitalcity, "Capital is not defined.") if self.capitalcity.nil?
    
    missing_translation  = self.translations.detect {|trans| trans.printable_name.blank? }
    self.errors.add(:translations, "There are missing translations") if missing_translation
    
    missing_translation.nil? and !self.capitalcity.nil?
  end

  def set_default_values
    if !self.deleted then
      self.name = self.printable_name.mb_chars.upcase.wrapped_string rescue self.name
      assign_location if self.name_changed? || self.printable_name_changed?
    end
  end        

  def can_destroy
    if self.stores.count > 0 then
      self.errors.add :general, "There are still stores defined assigned to #{self.name}" 
      false
    else
      true
    end
  end

  def self.list
     self.all(:include => [:region])
  end
  
  def region_name
    if self.region then
      region.name
    else
      "<NOT ASSIGNED>"
    end
  end
  
  def self.columns_for_index
     [ {:label => "Name", :method => :name, :order => "countries.printable_name" },
       {:label => "Region", :method => :region_name, :order => "regions.name" },
       {:label => "Updated On", :method => :updated_on_string, :order => "countries.updated_at"}  ]
   end
    
  def update_location
    self.lng = nil
    self.lat = nil
    self.assign_location
    if self.lng && self.lat then
      self.save!
    else
      p "location not found: #{self.name}"
    end 
  end
  
  def assign_location
    if (self.lng.nil? || self.lat.nil?) && (self.name) then
      location = Storelocator::Location.geocode("#{self.name}")
      self.lng = location.lng
      self.lat = location.lat
    end
  end

end
