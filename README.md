# mongo_ha

High availability for the mongo ruby driver. Automatic reconnects and recovery when replica-set changes, etc.

## Status

Production Ready: Used every day in an enterprise environment across
remote data centers.

## Overview

Tired of the mongo ruby driver throwing exceptions just because a server in the
replica-set starts or stops?

`mongo_ha` quietly handles replica-set changes, replica-set master re-election,
and transient network failures without blowing up your application.

This gem does not replace the `mongo` ruby driver, it adds methods and patches
others in the Mongo Ruby driver to make it support automatic reconnection and
retries on connection failure.

In the event of a connection failure, only one thread will attempt to re-establish
connectivity to the Mongo server(s). This is to prevent swamping the mongo
servers with reconnect attempts.

Retries are initially performed quickly in case it is a brief network issue
and then backs off to give the replica-set time to elect a new master.

Currently Only Supports Ruby Mongo driver v1.11.x. Submit an issue if other versions
need support too.

`mongo_ha` transparently supports `MongoMapper` since it uses the mongo ruby driver
that is patched by loading this gem. Earlier versions of Mongoid will also benefit
from `mongo_ha`, the latest version of Mongoid uses Moped that should be avoided and is
due to be replaced.

Mongo Router processes will often return a connection failure on their side
as an OperationFailure. This code will also retry automatically when the router
has errors talking to a sharded cluster.

## Mongo Cursors

Any operations that return a cursor need to be handled in your own code
since the retry cannot be handled transparently.
For example: `find` returns a cursor, whereas `find_one` is handled because
it returns the data returned rather than a cursor

Example

```ruby
# Wrap existing cursor based calls with a retry on connection failure block
results_collection.retry_on_connection_failure do
  results_collection.find({}, sort: '_id', timeout: false) do |cursor|
    cursor.each do |record|
      puts "Record: #{record.inspect}"
    end
  end
end
```

### Note

In the above example the block will be repeated from the _beginning_ of the
collection should a connection failure occur. Without appropriate handling it
is possible to read the same records twice.

If the collection cannot be processed twice, it may be better to just let the
`Mongo::ConnectionFailure` flow up into the application for it to deal with at
a higher level.

## Installation

Add to Gemfile:

```ruby
gem 'mongo_ha'
```

Or for standalone environments

```shell
gem install mongo_ha
```

If you are also using SemanticLogger, place `mongo_ha` below `semantic_logger`
and/or `rails_semantic_logger` in the `Gemfile`. This way it will create a logger
just for `Mongo::MongoClient` to improve the log output during connection recovery.

## Configuration

mongo_ha adds several new configuration options to fine tune the reconnect behavior
for any environment.

Sample mongo.yml:

```yaml
default_options: &default_options
  :w:                           1
  :pool_size:                   5
  :pool_timeout:                5
  :connect_timeout:             5
  :reconnect_attempts:          53
  :reconnect_retry_seconds:     0.1
  :reconnect_retry_multiplier:  2
  :reconnect_max_retry_seconds: 5

development: &development
  uri: mongodb://localhost:27017/development
  options:
    <<: *default_options

test:
  uri: mongodb://localhost:27017/test
  options:
    <<: *default_options

# Sample Production Settings
production:
  uri: mongodb://mongo1.site.com:27017,mongo2.site.com:27017/production
  options:
    <<: *default_options
    :pool_size:    50
    :pool_timeout: 5
```

The following options can be specified in the Mongo configuration options
to tune the retry intervals during a connection failure

### :reconnect_attempts

* Number of times to attempt to reconnect.
* Default: 53

### :reconnect_retry_seconds

* Initial delay before retrying
* Default: 0.1

### :reconnect_retry_multiplier

* Multiply delay by this number with each retry to prevent overwhelming the server
* Default: 2

### :reconnect_max_retry_seconds

* Maximum number of seconds to wait before retrying again
* Default: 5

Using the above default values, will result in retry connects at the following intervals

   0.1 0.2 0.4 0.8 1.6 3.2 5 5 5 5  ....

## Testing

There is really only one place to test something like `mongo_ha` and that is in
a high volume mission critical production environment.
The initial code in this gem was created over 2 years with MongoDB running in an
enterprise production environment with hundreds of connections to Mongo servers
in remote data centers across a WAN. It adds high availability to standalone
MongoDB servers, replica-sets, and sharded clusters.

## Issues

If the following output appears after adding the above connection options:

```shell
reconnect_attempts is not a valid option for Mongo::MongoClient
reconnect_retry_seconds is not a valid option for Mongo::MongoClient
reconnect_retry_multiplier is not a valid option for Mongo::MongoClient
reconnect_max_retry_seconds is not a valid option for Mongo::MongoClient
```

Then the `mongo_ha` gem was not loaded prior to connecting to Mongo
