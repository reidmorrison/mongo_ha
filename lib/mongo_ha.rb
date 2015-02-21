require 'mongo'
require 'mongo_ha/version'
require 'mongo_ha/mongo_client'

# Add in retry methods
Mongo::MongoClient.send(:include, MongoHA::MongoClient::InstanceMethods)

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
