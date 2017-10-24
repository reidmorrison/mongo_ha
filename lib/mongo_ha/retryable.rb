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
        cluster.sharded? ? sleep(cluster.read_retry_interval) : cluster.scan!
        retry
      end
    end

    def write_with_retry(session, server_selector)
      attempt = 0
      begin
        attempt += 1
        yield(server_selector.call)
      rescue Error::SocketError, Error::SocketTimeoutError => e
        raise(e) if attempt > cluster.max_read_retries
        log_retry(e)
        cluster.scan!
        retry
      rescue Error::OperationFailure => e
        raise(e) if !e.write_retryable? || (attempt > cluster.max_read_retries)
        log_retry(e)
        cluster.scan!
        retry
      end
    end

  end
end
