# mongo_ha

High availability for the mongo ruby driver. Automatic reconnects and recovery when replica-set changes, etc.

## Status

Most of the features of this gem were accepted into the mongo-ruby-client gem. :tada:

There are still a few outstanding changes:
* Retry on writes due to a master change.
* Retry on writes due to loss of network connectivity.
* Retry on reads during an operation failure other than when in a cluster.

## Note

In order to use mongo_ha with the Mongo Ruby Client v2.4 or greater it requires the latest code from master. 

To use V2.4 or greater add the following to your `Gemfile`:

~~~ruby
gem 'mongo', git: 'https://github.com/mongodb/mongo-ruby-driver.git'
gem 'mongo_ha', git: 'https://github.com/reidmorrison/mongo_ha.git'
~~~

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

Supports Ruby Mongo driver V1 and V2

`mongo_ha` transparently supports `MongoMapper` and `Mongoid` which use the mongo ruby driver.

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

## Testing

There is really only one place to test something like `mongo_ha` and that is in
a high volume mission critical production environment.
This gem was created and tested with MongoDB running in an
enterprise production environment with hundreds of connections to Mongo servers
in remote data centers across a WAN. It adds high availability to standalone
MongoDB servers, replica-sets, and sharded clusters.
