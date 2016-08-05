require 'mongo'
module MongoHA
  module MongoClient
    CONNECTION_RETRY_OPTS    = [:reconnect_attempts, :reconnect_retry_seconds, :reconnect_retry_multiplier, :reconnect_max_retry_seconds]

    # The following errors occur when mongos cannot connect to the shard
    # They require a retry to resolve them
    # This list was created through painful experience. Add any new ones as they are discovered
    #   9001: socket exception
    #   Operation failed with the following exception: Unknown error - Connection reset by peer:Unknown error - Connection reset by peer
    #   DBClientBase::findOne: transport error
    #   : db assertion failure
    #   8002: 8002 all servers down!
    #   Operation failed with the following exception: stream closed
    #   Operation failed with the following exception: Bad file descriptor - Bad file descriptor:Bad file descriptor - Bad file descriptor
    #   Failed to connect to primary node.
    #   10009: ReplicaSetMonitor no master found for set: mdbb
    OPERATION_FAILURE_ERRORS = [
      'socket exception',
      'Connection reset by peer',
      'transport error',
      'db assertion failure',
      '8002',
      'stream closed',
      'Bad file descriptor',
      'Failed to connect',
      '10009',
      'no master found',
      'not master',
      'Timed out waiting on socket',
      "didn't get writeback",
      'interrupted at shutdown'
    ]

    module InstanceMethods
      # Add retry logic to MongoClient
      def self.included(base)
        base.class_eval do
          # Give MongoClient a class-specific logger if SemanticLogger V2.12 or above is available
          # to give better logging information during a connection recovery scenario
          if defined?(SemanticLogger::DebugAsTraceLogger)
            # Map Debug level calls to trace to reduce log file clutter
            @@logger = SemanticLogger::DebugAsTraceLogger.new(self)

            def self.logger
              @@logger
            end

            def logger
              self.class.logger
            end
          end

          alias_method :valid_opts_original, :valid_opts
          alias_method :setup_original, :setup

          attr_accessor *CONNECTION_RETRY_OPTS

          # Prevent multiple threads from trying to reconnect at the same time during
          # connection failures
          @@failover_mutex = Mutex.new

          private

          def valid_opts(*args)
            valid_opts_original(*args) + CONNECTION_RETRY_OPTS
          end

          def setup(opts)
            self.reconnect_attempts          = (opts.delete(:reconnect_attempts) || 53).to_i
            self.reconnect_retry_seconds     = (opts.delete(:reconnect_retry_seconds) || 0.1).to_f
            self.reconnect_retry_multiplier  = (opts.delete(:reconnect_retry_multiplier) || 2).to_f
            self.reconnect_max_retry_seconds = (opts.delete(:reconnect_max_retry_seconds) || 5).to_f
            setup_original(opts)
          end

        end
      end

      # Retry the supplied block when a Mongo::ConnectionFailure occurs
      #
      # Note: Check for Duplicate Key on inserts
      #
      # Returns the result of the block
      #
      # Example:
      #   connection.retry_on_connection_failure { |retried| connection.ping }
      def retry_on_connection_failure(&block)
        raise 'Missing mandatory block parameter on call to Mongo::Connection#retry_on_connection_failure' unless block
        # No need to double retry calls
        return block.call(false) if Thread.current[:mongo_ha_active?]
        retried        = false
        mongos_retries = 0
        begin
          Thread.current[:mongo_ha_active?] = true
          result                      = block.call(retried)
          retried                     = false
          result
        rescue Mongo::ConnectionFailure => exc
          # Retry if reconnected, but only once to prevent an infinite loop
          logger.warn "Connection Failure: '#{exc.message}' [#{exc.error_code}]"
          if !retried && _reconnect
            retried = true
            retry
          end
          raise exc
        rescue Mongo::AuthenticationError => exc
          # Retry once due to rare failures during authentication against MongoDB V3 servers
          logger.warn "Authentication Failure: '#{exc.message}' [#{exc.error_code}]"
          if !retried && _reconnect
            retried = true
            retry
          end
          raise exc
        rescue Mongo::OperationFailure => exc
          # Workaround not master issue. Disconnect connection when we get a not master
          # error message. Master checks for an exact match on "not master", whereas
          # it sometimes gets: "not master and slaveok=false"
          if exc.result
            error = exc.result['err'] || exc.result['errmsg']
            close if error && error.include?('not master')
          end

          # These get returned when connected to a local mongos router when it in turn
          # has connection failures talking to the remote shards. All we do is retry the same operation
          # since it's connections to multiple remote shards may have failed.
          # Disconnecting the current connection will not help since it is just to the mongos router
          # First make sure it is connected to the mongos router
          raise exc unless (OPERATION_FAILURE_ERRORS.any? { |err| exc.message.include?(err) }) || (exc.message.strip == ':')

          mongos_retries += 1
          if mongos_retries <= 60
            retried = true
            Kernel.sleep(0.5)
            logger.warn "[#{primary.inspect}] Router Connection Failure. Retry ##{mongos_retries}. Exc: '#{exc.message}' [#{exc.error_code}]"
            retry
          end
          raise exc
        ensure
          Thread.current[:mongo_ha_active?] = false
        end
      end

      private

      # Call this method whenever a Mongo::ConnectionFailure Exception
      # has been raised to re-establish the connection
      #
      # This method is thread-safe and ensure that only one thread at a time
      # per connection will attempt to re-establish the connection
      #
      # Returns whether the connection is connected again
      def _reconnect
        logger.debug 'Going to reconnect'

        # Prevent other threads from invoking reconnect logic at the same time
        @@failover_mutex.synchronize do
          # Another thread may have already failed over the connection by the
          # time this threads gets in
          begin
            ping
          rescue Mongo::ConnectionFailure
            # Connection still not available, run code below
          end

          if active?
            logger.info "Connected to: #{primary.inspect}"
            return true
          end

          if reconnect_attempts > 0
            # Wait for other threads to finish working on their sockets
            retries       = 1
            retry_seconds = reconnect_retry_seconds
            begin
              logger.warn "Connection unavailable. Waiting: #{retry_seconds} seconds before retrying"
              sleep retry_seconds
              ping
            rescue Mongo::ConnectionFailure => exc
              if retries < reconnect_attempts
                retries       += 1
                retry_seconds *= reconnect_retry_multiplier
                retry_seconds = reconnect_max_retry_seconds if retry_seconds > reconnect_max_retry_seconds
                retry
              end

              logger.error "Auto-reconnect giving up after #{retries} reconnect attempts"
              raise exc
            end
            logger.info "Successfully reconnected to: #{primary.inspect}"
          end
          connected?
        end
      end

    end
  end
end
