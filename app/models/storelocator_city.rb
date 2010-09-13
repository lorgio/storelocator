=begin
StorelocatorCity.rb
Copyright 2009 wollzelle GmbH (http://wollzelle.com). All rights reserved.
=end

class StorelocatorCity < Storelocator::Base
  set_table_name "cities"
  
  belongs_to :country, :class_name => 'StorelocatorCountry'
  has_many   :stores,  :class_name => 'StorelocatorStore', :foreign_key => 'city_id'
  
  validates_presence_of   :country, :message => "Country can't be blank."
  validates_presence_of   :name, :message => "Unique name can't be blank."
  validates_presence_of   :printable_name => "City name can't be blank."
  
  named_scope :with_location, :conditions => ['lat+lng is not null']
  named_scope :capitals, :conditions => 'exists (select 1 from countries where capitalcity_id=cities.id)'
  named_scope :in_country, lambda {|country| 
    id = country.id rescue -1
    {:conditions => ['cities.country_id = :country_id', {:country_id => id }] } }
      
  acts_as_wz_translateable :table_name => 'city_translations', :foreign_key => 'city_id'
  acts_as_wz_publishable :override_all_method => false, :uses_soft_delete => true, :revisioning => false

  before_destroy :can_destroy
  
  before_save   :set_default_values
  before_create :verify_name_uniqueness_create
  before_save   :verify_name_uniqueness_save
  
  def verify_name_uniqueness_create
    if !self.archived then  # archive - entry
      city = StorelocatorCity.latest.first(:conditions => ["deleted = false and name = :name and country_id = :country_id and id <> :id", 
                                    {:name => self.name, :country_id => self.country_id, :id => self.id || -1 }])
      self.errors.add(:name, "A city with the same name already exists.") if city
      city.nil?
    else
      true
    end
  end
  
  def self.get_unique_name(name)
    chk_name = name
    cnt = 2
    city = StorelocatorCity.latest.first(:conditions => ["deleted = false and upper(name) = :name and country_id = :country_id ", 
                                  {:name => chk_name.upcase.wrapped_string, :country_id => self.country_id, :id => self.id }])
    while city and (cnt<30) do
      chk_name = "#{name} (#{cnt})"
      city = StorelocatorCity.latest.first(:conditions => ["deleted = false and upper(name) = :name and country_id = :country_id ", 
                                    {:name => chk_name.upcase.wrapped_string, :country_id => self.country_id }])      
    end
    chk_name 
  end

  def self.named_stripped(name)
    name.split(/(.*)\(.*\)/)[1].mb_chars.strip.wrapped_string rescue name
  end

  def verify_name_uniqueness_save
    if !self.archived then # archive - entry
      if name_changed? then
        if !new_record? and (self.stores.count>0) then
          self.errors.add(:name, "Name can't be changed, because there are already stores assigned.")
          return false
        end
        city = StorelocatorCity.latest.first(:conditions => ["deleted = false and upper(name) = :name and country_id = :country_id and (id <> :id) and (publish_id is null or publish_id <> :id)", 
                                      {:name => self.name.mb_chars.upcase.wrapped_string, :country_id => self.country_id, :id => self.id }])
        self.errors.add(:name, "a city with this name already exists") if city
        city.nil?
      else
        true
      end
    end
  end
  
  def capitalcity?
    (self.country.capitalcity == self)
  end
  
  def set_default_values
    self.name = self.printable_name if self.name.nil?
    assign_location if self.name_changed? || self.printable_name_changed?
    true
  end                  

  def can_destroy
    if self.capitalcity? then
      self.errors.add :general, "The capital city can not be deleted." 
      return false
    else
      if self.stores.count > 0 then
        self.errors.add :general, "The capital city can not be deleted." 
        return false
      end  
    end
    true
  end

  def update_location
    self.lng = nil
    self.lat = nil
    self.assign_location
    if self.lng && self.lat then
      self.save!
    else
      p "location not found: #{self.name}, #{self.country.name}"
    end 
  end

  # location work better with country codes on googlemaps
  def assign_location
    if (self.lng.nil? || self.lat.nil? || self.printable_name_changed? || self.name_changed?) && (self.name && self.country) then
      location = Storelocator::Location.geocode("#{self.name}", self.country)
      self.lng = location.lng
      self.lat = location.lat
    end
  end


end
