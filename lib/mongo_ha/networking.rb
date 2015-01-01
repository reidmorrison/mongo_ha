module MongoHA
  module Networking
    module InstanceMethods
      def self.included(base)
        base.class_eval do
          # Fix problem where a Timeout exception is not checking the socket back into the pool
          #   Based on code from Gem V1.11.1, not needed with V1.12 or above
          #   Only change is the ensure block
          def send_message_with_gle(operation, message, db_name, log_message=nil, write_concern=false)
            docs = num_received = cursor_id = ''
            add_message_headers(message, operation)

            last_error_message = build_get_last_error_message(db_name, write_concern)
            last_error_id = add_message_headers(last_error_message, Mongo::Constants::OP_QUERY)

            packed_message = message.append!(last_error_message).to_s
            sock = nil
            begin
              sock = checkout_writer
              send_message_on_socket(packed_message, sock)
              docs, num_received, cursor_id = receive(sock, last_error_id)
#              Removed checkin
#              checkin(sock)
            rescue Mongo::ConnectionFailure, Mongo::OperationFailure, Mongo::OperationTimeout => ex
#              Removed checkin
#              checkin(sock)
              raise ex
            rescue SystemStackError, NoMemoryError, SystemCallError => ex
              close
              raise ex
#           Added ensure block to always check sock back in
            ensure
              checkin(sock) if sock
            end

            if num_received == 1
              error = docs[0]['err'] || docs[0]['errmsg']
              if error && error.include?("not master")
                close
                raise Mongo::ConnectionFailure.new(docs[0]['code'].to_s + ': ' + error, docs[0]['code'], docs[0])
              elsif (!error.nil? && note = docs[0]['jnote'] || docs[0]['wnote']) # assignment
                code = docs[0]['code'] || Mongo::ErrorCode::BAD_VALUE # as of server version 2.5.5
                raise Mongo::WriteConcernError.new(code.to_s + ': ' + note, code, docs[0])
              elsif error
                code = docs[0]['code'] || Mongo::ErrorCode::UNKNOWN_ERROR
                error = "wtimeout" if error == "timeout"
                raise Mongo::WriteConcernError.new(code.to_s + ': ' + error, code, docs[0]) if error == "wtimeout"
                raise Mongo::OperationFailure.new(code.to_s + ': ' + error, code, docs[0])
              end
            end

            docs[0]
          end
        end
      end
    end
  end
end