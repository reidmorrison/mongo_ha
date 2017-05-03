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
        log_retry(e)
        cluster.scan!
        retry
      rescue Error::OperationFailure => e
        raise(e) if !e.retryable? || (attempt > cluster.max_read_retries)
        log_retry(e)
        if cluster.sharded?
          # We don't scan the cluster in this case as Mongos always returns
          # ready after a ping no matter what the state behind it is.
          sleep(cluster.read_retry_interval)
        else
          cluster.scan!
        end
        retry
      end
    end

    def write_with_retry
      attempt = 0
      begin
        attempt += 1
        yield
      rescue Error::SocketError, Error::SocketTimeoutError => e
        raise(e) if attempt > cluster.max_read_retries
        log_retry(e)
        # During a replicaset master change the primary immediately closes all existing client connections.
        #
        # Note:
        #   Small possibility the write occurs twice.
        #   Usually this is acceptable since most applications would just retry the write anyway.
        #   The ideal way is to check if the write succeeded, or just use a primary key to
        #   prevent multiple writes etc.
        #   In production we have not seen duplicates using this retry mechanism.
        cluster.scan!
        retry
      rescue Error::OperationFailure => e
        raise(e) if !e.write_retryable? || (attempt > cluster.max_read_retries)
        log_retry(e)
        if cluster.sharded?
          # We don't scan the cluster in this case as Mongos always returns
          # ready after a ping no matter what the state behind it is.
          sleep(cluster.read_retry_interval)
        else
          cluster.scan!
        end
        retry
      end
    end

  end
end
