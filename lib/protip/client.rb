require 'active_support/concern'
require 'protip/error'
require 'net/http'
require 'resolv-replace'

module Protip
  module Client
    extend ActiveSupport::Concern

    attr_accessor :base_uri

    # Makes a request and parses the response as a message of the given type.
    # For internal use only; use the appropriate resource to make your requests.
    #
    # @param path [String] the URI path (exluding the base URI)
    # @param method [Class] the HTTP method (e.g. `::Net::HTTP::Get`, `::Net::HTTP::Post`)
    # @param message [Protobuf::Message|nil] the message to send as the request body
    # @param response_type [Class] the `::Protobuf::Message` subclass that should be
    #   expected as a response
    # @return [::Protobuf::Message] the decoded response from the server
    def request(path:, method:, message:, response_type:)

      raise RuntimeError.new('base_uri is not set') unless base_uri

      uri = URI.join base_uri, path

      request                 = method.new uri
      request.body            = (message ? message.class.encode(message) : nil)
      request['Accept']       = 'application/x-protobuf'
      request.content_type    = 'application/x-protobuf'

      prepare_request(request)

      # TODO: Shared connection object for persisent connections.
      response = execute_request(request)

      if response.is_a?(Net::HTTPUnprocessableEntity)
        raise ::Protip::UnprocessableEntityError.new(request, response)
      elsif response.is_a?(Net::HTTPNotFound)
        raise ::Protip::NotFoundError.new(request, response)
      elsif !response.is_a?(Net::HTTPSuccess)
        raise ::Protip::Error.new(request, response)
      end

      if response_type
        begin
          response_type.decode response.body
        rescue StandardError => error
          raise ::Protip::ParseError.new error, request, response
        end
      else
        nil
      end
    end

    private

    # Invoked just before a request is sent to the API server. No-op by default, but
    # implementations can override to add e.g. secret keys and user agent headers.
    #
    # @param request [Net::HTTPGenericRequest] the raw request object which is about to be sent
    def prepare_request(request)
      # No-op by default.
    end

    # Helper for obtaining the API server's response, overridable if any special handling
    # is needed.
    # TODO: (possibly) merge this with +prepare_request+
    #
    # @param request [Net::HTTPGenericRequest] the raw request object to send
    # @return [Net::HTTPResponse] the response for the given request
    def execute_request(request)
      http = nil
      uri = request.uri
      retries = 0
      max_retries = 3

      begin
        unless http
          http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 120)
        end
        http.request request
      rescue Net::OpenTimeout, Net::ReadTimeout
        if (retries += 1) <= max_retries
          sleep(retries)
          retry
        else
          raise
        end
      ensure
        if http
          http.finish
        end
      end
    end
  end
end
