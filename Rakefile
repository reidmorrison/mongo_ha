require 'rake/clean'
require 'rake/testtask'

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require 'mongo_ha/version'

task :gem do
  system "gem build mongo_ha.gemspec"
end

task :publish => :gem do
  system "git tag -a v#{MongoHA::VERSION} -m 'Tagging #{MongoHA::VERSION}'"
  system "git push --tags"
  system "gem push mongo_ha-#{MongoHA::VERSION}.gem"
  system "rm mongo_ha-#{MongoHA::VERSION}.gem"
end
