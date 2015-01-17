require 'mongo'
require 'mongo_ha/version'
require 'mongo_ha/mongo_client'
require 'mongo_ha/networking'

# Give MongoClient a class-specific logger if SemanticLogger is available
# to give better logging information during a connection recovery scenario
if defined?(SemanticLogger)
  Mongo::MongoClient.send(:include, SemanticLogger::Loggable)
  Mongo::MongoClient.send(:define_method, :logger) { super() }
end

# Add in retry methods
Mongo::MongoClient.send(:include, MongoHA::MongoClient::InstanceMethods)

# Ensure connection is checked back into the pool when exceptions are thrown
#   The following line is no longer required with Mongo V1.12 and above
Mongo::Networking.send(:include, MongoHA::Networking::InstanceMethods)

# Wrap critical Mongo methods with retry_on_connection_failure
{
  Mongo::Collection                => [
    :aggregate, :count, :capped?, :distinct, :drop, :drop_index, :drop_indexes,
    :ensure_index, :find_one, :find_and_modify, :group, :index_information,
    :options, :stats, :map_reduce
  ],
  Mongo::CollectionOperationWriter => [:send_write_operation, :batch_message_send],
  Mongo::CollectionCommandWriter   => [:send_write_command, :batch_message_send]

}.each_pair do |klass, methods|
  methods.each do |method|
    original_method = "#{method}_original".to_sym
    klass.send(:alias_method, original_method, method)
    klass.send(:define_method, method) do |*args|
      @connection.retry_on_connection_failure { send(original_method, *args) }
    end
  end
end
