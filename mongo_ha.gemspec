lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

# Maintain your gem's version:
require 'mongo_ha/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'mongo_ha'
  s.version     = MongoHA::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Reid Morrison']
  s.email       = ['reidmo@gmail.com']
  s.homepage    = 'https://github.com/reidmorrison/mongo_ha'
  s.summary     = "High availability for the mongo ruby driver"
  s.description = "Automatic reconnects and recovery when replica-set changes, or connections are lost, with transparent recovery"
  s.files       = Dir["lib/**/*", "LICENSE.txt", "Rakefile", "README.md"]
  s.test_files  = Dir["test/**/*"]
  s.license     = "Apache License V2.0"
  s.has_rdoc    = true
  s.add_dependency 'mongo', '~> 1.11.0'
end
