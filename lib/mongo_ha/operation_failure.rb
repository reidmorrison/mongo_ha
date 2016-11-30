require 'mongo/error/operation_failure'

module Mongo
  class Error
    class OperationFailure
      WRITE_RETRY_MESSAGES = [
        'no master',
        'not master',
        'could not contact primary',
        'Not primary'
      ]

      remove_const :RETRY_MESSAGES
      RETRY_MESSAGES = WRITE_RETRY_MESSAGES + [
        'transport error',
        'socket exception',
        "can't connect",
        'connect failed',
        'error querying',
        'could not get last error',
        'connection attempt failed',
        'interrupted at shutdown',
        'unknown replica set',
        'dbclient error communicating with server'
      ]

      def write_retryable?
        WRITE_RETRY_MESSAGES.any? { |m| message.include?(m) }
      end

    end
  end
end

