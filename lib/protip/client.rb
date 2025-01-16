# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/deprecation'
require 'protip/error'
require 'net/http'
require 'faraday'

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
      response = client.send(remap_method(method), path) do |req|
        req.body = message ? message.class.encode(message) : ''

        prepare_request(req.headers)
      end

      request = response.env.request

      if response.status == 422
        raise ::Protip::UnprocessableEntityError.new(request, response)
      elsif response.status == 404
        raise ::Protip::NotFoundError.new(request, response)
      elsif !response.success?
        raise ::Protip::Error.new(request, response)
      end

      if response_type
        begin
          response_type.decode(response.body || '')
        rescue StandardError => error
          raise ::Protip::ParseError.new(error, request, response)
        end
      else
        nil
      end
    end

    private

    def remap_method(method)
      return :get if method == :get || method == Net::HTTP::Get
      return :head if method == :head || method == Net::HTTP::Head
      return :post if method == :post || method == Net::HTTP::Post
      return :put if method == :put || method == Net::HTTP::Put
      return :patch if method == :patch || method == Net::HTTP::Patch
      return :delete if method == :delete || method == Net::HTTP::Delete
      return :options if method == :options || method == Net::HTTP::Options
      raise RuntimeError.new("unknown method #{method}")
    end

    def client
      raise RuntimeError.new('base_uri is not set') unless base_uri

      Faraday.new({
        url: base_uri,
        headers: {
          'Accept' => 'application/x-protobuf',
          'Content-Type' => 'application/x-protobuf',
        },
        request: {
          timeout: 600,
        },
      })
    end

    # Invoked just before a request is sent to the API server. No-op by default, but
    # implementations can override to add e.g. secret keys and user agent headers.
    #
    # @param request [Net::HTTPGenericRequest] the raw request object which is about to be sent
    def prepare_request(request)
      # No-op by default.
    end
  end
end
