require 'mongo/retryable'

module Mongo
  module Retryable

    def read_with_retry
      attempt = 0
      begin
        attempt += 1
        yield
      rescue Error::SocketError, Error::SocketTimeoutError => e
        raise(e) if attempt > cluster.max_read_retries
        retry_reconnect(e)
        retry
      rescue Error::OperationFailure => e
        if cluster.sharded? && e.retryable?
          if attempt < cluster.max_read_retries
            # We don't scan the cluster in this case as Mongos always returns
            # ready after a ping no matter what the state behind it is.
            sleep(cluster.read_retry_interval)
            retry
          else
            raise e
          end
        else
          raise e
        end
      end
    end

    def read_with_one_retry
      yield
    rescue Error::SocketError, Error::SocketTimeoutError => e
      retry_reconnect(e)
      yield
    end

    def write_with_retry
      attempt = 0
      begin
        attempt += 1
        yield
      rescue Error::SocketError => e
        raise(e) if attempt >= cluster.max_read_retries
        # During a replicaset master change the primary immediately closes all existing client connections.
        #
        # Note:
        #   Small possibility the write occurs twice.
        #   Usually this is acceptable since most applications would just retry the write anyway.
        #   The ideal way is to check if the write succeeded, or just use a primary key to
        #   prevent multiple writes etc.
        #   In production we have not seen duplicates using this retry mechanism.
        retry_reconnect(e)
        retry
      rescue Error::OperationFailure => e
        raise(e) if attempt >= cluster.max_read_retries
        if e.write_retryable?
          retry_reconnect(e)
          retry
        else
          raise(e)
        end
      end
    end

    private

    def retry_reconnect(e)
      Logger.logger.warn "Retry due to: #{e.class.name} #{e.message}"
      sleep(cluster.read_retry_interval)
      cluster.scan!
    end

  end
end
