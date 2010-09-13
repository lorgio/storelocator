=begin
region.rb
Copyright 2009 wollzelle GmbH (http://wollzelle.com). All rights reserved.
=end

class StorelocatorRegion < Storelocator::Base
  set_table_name "regions"
  
  acts_as_wz_translateable :table_name => 'region_translations', :foreign_key => 'region_id'
  acts_as_wz_publishable :override_all_method => false, :uses_soft_delete => true, :revisioning => false
    
  has_many :countries, :class_name => 'StorelocatorCountry', :foreign_key => 'region_id'

  validates_presence_of :printable_name, :message => "Region name can't be blank."
  validates_uniqueness_of :name, :message => "A region with the same name already exists."                 

  named_scope :with_countries, :conditions => 'exists (select id from countries where region_id = regions.id)'
  
  before_destroy :can_destroy
  before_save :set_default_values
  
  before_publish :check_before_publish

  def check_before_publish
    missing_translation  = translations.detect {|trans| trans.printable_name.blank? }
    self.errors.add(:translations, "Translation is missing!") if missing_translation
    missing_translation.nil?
  end

  def set_default_values
    self.name = self.printable_name.mb_chars.upcase.wrapped_string rescue self.name
  end        

  def can_destroy
    if self.countries.count > 0 then
      self.errors.add :general, "There are still countries assigned to #{self.name}" 
      false
    else
      true
    end
  end  
  
end