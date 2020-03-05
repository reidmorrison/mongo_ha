require 'mongo/retryable'
require 'timeout'

module Mongo
  module Retryable
    def legacy_write_with_retry(server = nil, session = nil)
      attempt = 0
      begin
        attempt += 1
        yield(server || cluster.next_primary)
      rescue Error::SocketError, Error::SocketTimeoutError, Timeout::Error => e
        server = nil
        # Mongo also raises the generic Timeout, so check the backtrace to make sure it was from mongo.
        raise(e) if e.is_a?(::Timeout::Error) && e.backtrace && !e.backtrace.first.include?("/mongo/")
        raise(e) if attempt > cluster.max_read_retries || (session && session.in_transaction?)
        log_retry(e)
        cluster.scan!
        retry
      rescue Error::OperationFailure => e
        server = nil
        raise(e) if attempt > cluster.max_read_retries
        if e.write_retryable? && !(session && session.in_transaction?)
          log_retry(e)
          cluster.scan!
          retry
        else
          raise(e)
        end
      end
    end
  end
end
