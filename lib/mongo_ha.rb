require 'mongo'
require 'mongo_ha/version'
require 'mongo_ha/mongo_client'

# Add in retry methods
Mongo::MongoClient.send(:include, MongoHA::MongoClient::InstanceMethods)

# Wrap critical Mongo methods with retry_on_connection_failure
{
  # Most calls use a cursor under the covers to return the result
  # If the primary is lost and it connects to a different server an expired cursor exception is raised
  Mongo::Cursor     => [:refresh],

  # These methods do not use a Cursor
  Mongo::Collection => [:insert, :remove, :update]
}.each_pair do |klass, methods|
  methods.each do |method|
    original_method = "#{method}_original".to_sym
    klass.send(:alias_method, original_method, method)
    klass.send(:define_method, method) do |*args|
      @connection.retry_on_connection_failure { send(original_method, *args) }
    end
  end
end

# Drop the max ping time to a more respectable time. Assuming it is in ms.
Mongo::Pool.send(:remove_const, :MAX_PING_TIME)
Mongo::Pool::MAX_PING_TIME = 5_000
