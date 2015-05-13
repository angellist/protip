# Missing dependency from the protobuf require
require 'protobuf'

require 'protip/messages/errors.pb'

module Protip
  class Error < RuntimeError
    attr_reader :request, :response
    def initialize(request, response)
      @request = request
      @response = response
    end

    def inspect
      "[#{self.class}] #{request.uri} -> code #{response.code}"
    end
  end

  class ParseError < Error
    attr_reader :original_error
    def initialize(original_error, *args)
      super(*args)
      @original_error = original_error
    end
  end

  class UnprocessableEntityError < Error
    # Get the parsed errors object from a 422 response.
    #
    # @return ::Protip::Messages::Errors
    def errors
      ::Protip::Messages::Errors.decode response.body
    end
  end

  class NotFoundError < Error ; end
end
