require 'mongo'
module MongoHA
  module MongoClient
    CONNECTION_RETRY_OPTS = [:reconnect_attempts, :reconnect_retry_seconds, :reconnect_retry_multiplier, :reconnect_max_retry_seconds]

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
    MONGOS_CONNECTION_ERRORS = [
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

          alias_method :receive_message_original, :receive_message
          alias_method :connect_original, :connect
          alias_method :valid_opts_original, :valid_opts
          alias_method :setup_original, :setup

          attr_accessor *CONNECTION_RETRY_OPTS

          # Prevent multiple threads from trying to reconnect at the same time during
          # connection failures
          @@failover_mutex = Mutex.new
          # Wrap internal networking calls with retry logic

          # Do not stub out :send_message_with_gle or :send_message
          # It modifies the message, see CollectionWriter#send_write_operation

          def receive_message(*args)
            retry_on_connection_failure do
              receive_message_original *args
            end
          end

          def connect(*args)
            retry_on_connection_failure do
              connect_original *args
            end
          end

          protected

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
        raise "Missing mandatory block parameter on call to Mongo::Connection#retry_on_connection_failure" unless block
        retried = false
        mongos_retries = 0
        begin
          result = block.call(retried)
          retried = false
          result
        rescue Mongo::ConnectionFailure => exc
          # Retry if reconnected, but only once to prevent an infinite loop
          logger.warn "Connection Failure: '#{exc.message}' [#{exc.error_code}]"
          if !retried && reconnect
            retried = true
            # TODO There has to be a way to flush the connection pool of all inactive connections
            retry
          end
          raise exc
        rescue Mongo::OperationFailure => exc
          # Workaround not master issue. Disconnect connection when we get a not master
          # error message. Master checks for an exact match on "not master", whereas
          # it sometimes gets: "not master and slaveok=false"
          if exc.result
            error = exc.result['err'] || exc.result['errmsg']
            close if error && error.include?("not master")
          end

          # These get returned when connected to a local mongos router when it in turn
          # has connection failures talking to the remote shards. All we do is retry the same operation
          # since it's connections to multiple remote shards may have failed.
          # Disconnecting the current connection will not help since it is just to the mongos router
          # First make sure it is connected to the mongos router
          raise exc unless (MONGOS_CONNECTION_ERRORS.any? { |err| exc.message.include?(err) }) || (exc.message.strip == ':')

          mongos_retries += 1
          if mongos_retries <= 60
            retried = true
            Kernel.sleep(0.5)
            logger.warn "[#{primary.inspect}] Router Connection Failure. Retry ##{mongos_retries}. Exc: '#{exc.message}' [#{exc.error_code}]"
            # TODO Is there a way to flush the connection pool of all inactive connections
            retry
          end
          raise exc
        end
      end

      # Call this method whenever a Mongo::ConnectionFailure Exception
      # has been raised to re-establish the connection
      #
      # This method is thread-safe and ensure that only one thread at a time
      # per connection will attempt to re-establish the connection
      #
      # Returns whether the connection is connected again
      def reconnect
        logger.debug "Going to reconnect"

        # Prevent other threads from invoking reconnect logic at the same time
        @@failover_mutex.synchronize do
          # Another thread may have already failed over the connection by the
          # time this threads gets in
          if active?
            logger.info "Connected to: #{primary.inspect}"
            return true
          end

          # Close all sockets that are not checked out so that other threads not
          # currently waiting on Mongo, don't get bad connections and have to
          # retry each one in turn
          @primary_pool.close if @primary_pool

          if reconnect_attempts > 0
            # Wait for other threads to finish working on their sockets
            retries = 1
            retry_seconds = reconnect_retry_seconds
            begin
              logger.warn "Connection unavailable. Waiting: #{retry_seconds} seconds before retrying"
              sleep retry_seconds
              # Call original connect method since it is already within a retry block
              connect_original
            rescue Mongo::ConnectionFailure => exc
              if retries < reconnect_attempts
                retries += 1
                retry_seconds *=  reconnect_retry_multiplier
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