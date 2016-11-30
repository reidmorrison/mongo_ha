require 'mongo/retryable'

module Mongo
  module Retryable

    def read_with_retry(attempt = 0, &block)
      begin
        block.call
      rescue Error::SocketError, Error::SocketTimeoutError => e
        retry_operation(e, &block)
      rescue Error::OperationFailure => e
        # TODO: Non sharded, retryable due to Replicaset primary change

        if cluster.sharded? && e.retryable?
          if attempt < cluster.max_read_retries
            # We don't scan the cluster in this case as Mongos always returns
            # ready after a ping no matter what the state behind it is.
            sleep(cluster.read_retry_interval)
            read_with_retry(attempt + 1, &block)
          else
            raise e
          end
        else
          raise e
        end
      end
    end

    def read_with_one_retry(&block)
      block.call
    rescue Error::SocketError, Error::SocketTimeoutError => e
      Logger.logger.warn "Single retry due to: #{e.class.name} #{e.message}"
      block.call
    end

    def write_with_retry(&block)
      begin
        block.call
      rescue Error::SocketError => e
        # During a master move in a replica-set the master closes existing client connections.
        # Note: Small possibility the write occurs twice.
        retry_operation(e, &block)
      rescue Error::OperationFailure => e
        if e.write_retryable?
          retry_operation(e, &block)
        else
          raise e
        end
      end
    end

    private

    # Log a warning on retry to prevent appearance of "hanging" during a failover.
    def retry_operation(e, &block)
      Logger.logger.warn "Retry due to: #{e.class.name} #{e.message}"
      cluster.scan!
      block.call
    end

  end
end
