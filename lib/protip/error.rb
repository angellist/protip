# Missing dependency from the protobuf require
require 'protobuf'

require 'protip/messages/errors.pb'

module Protip
  class Error < RuntimeError
    attr_reader :request, :response, :message
    def initialize(request, response, message=nil)
      @request = request
      @response = response
      @message = message
    end

    def inspect
      "[#{self.class}] #{request.uri} -> code #{response.code}"
    end

    def default_message
      [
        "request uri: #{request.uri}",
        "response code: #{response.code}",
        "response body: #{response.body}"
      ].join("\n")
    end

    def to_s
      message || default_message
    end
  end

  class ParseError < Error
    attr_reader :original_error
    def initialize(original_error, *args)
      super(*args)
      @original_error = original_error
    end
  end

  # Raised when we have a 422 response from the server.
  class UnprocessableEntityError < Error
    # Get the parsed errors object from a 422 response.
    #
    # @return ::Protip::Messages::Errors
    def errors
      ::Protip::Messages::Errors.decode response.body
    end

    def to_s
      message || errors.to_s
    end
  end

  class NotFoundError < Error ; end
end
