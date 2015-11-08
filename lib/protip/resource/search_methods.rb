module Protip
  module Resource
    # Internal handlers for index/show actions. Never use these directly; instead, use `.all` and
    # `.find` on the resource you're working with, since those methods will adjust their
    # signatures to correctly parse a set of query parameters if supported.
    module SearchMethods
      # Fetch a list from the server at the collection's base endpoint. Expects the server response
      # to be an array containing encoded messages that can be used to instantiate our resource.
      #
      # @param resource_class [Class] The resource type that we're fetching.
      # @param query [::Protobuf::Message|NilClass] An optional query to send along with the request.
      # @return [Array] The array of resources (each is an instance of the resource class we were
      #   initialized with).
      def self.index(resource_class, query)
        response = resource_class.client.request path: resource_class.base_path,
          method: Net::HTTP::Get,
          message: query,
          response_type: Protip::Messages::Array
        response.messages.map do |message|
          resource_class.new resource_class.message.decode(message)
        end
      end

      # Fetch a single resource from the server.
      #
      # @param resource_class [Class] The resource type that we're fetching.
      # @param id [String] The ID to be used in the URL to fetch the resource.
      # @param query [::Protobuf::Message|NilClass] An optional query to send along with the request.
      # @return [Protip::Resource] An instance of our resource class, created from the server
      #   response.
      def self.show(resource_class, id, query)
        response = resource_class.client.request path: "#{resource_class.base_path}/#{id}",
          method: Net::HTTP::Get,
          message: query,
          response_type: resource_class.message
        resource_class.new response
      end
    end
  end
end