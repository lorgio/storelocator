require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.files = Dir["{lib}/**/*", "{app}/**/*", "{config}/**/*", "{test}/**/*"]
    gem.files << 'README.rdoc'
    gem.files << 'VERSION'
    gem.files << 'LICENSE'
    gem.files << 'Rakefile'    
    
    gem.name = "storelocator"
    gem.summary = %Q{Storelocator}
    gem.description = %Q{Storelocator with regions, countries and cities and I18n }
    gem.email = "a.danmayer@wollzelle.com"
    gem.homepage = "http://github.com/wollzelle/storelocator"
    gem.authors = ["alexander danmayer"]
    gem.add_dependency "acts_as_wz_translateable", ">= 0.3"
    gem.add_dependency "acts_as_wz_publishable", ">= 0.1"
    gem.add_dependency "geokit", "1.5"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test' << 'app/models'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |test|
    test.libs << 'test'
    test.pattern = 'test/**/test_*.rb'
    test.verbose = true
  end
rescue LoadError
  task :rcov do
    abort "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
  end
end

task :test => :check_dependencies

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "storelocator #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
