module Protip
  module Resource
    # Internal helpers for non-resourceful member/collection methods. Never use these directly;
    # instead, use the instance/class methods which have been dynamically defined on the resource
    # you're working with.
    module ExtraMethods
      def self.member(resource, action, method, message, response_type)
        response = resource.class.client.request path: "#{resource.class.base_path}/#{resource.id}/#{action}",
          method: method,
          message: message,
          response_type: response_type
        nil == response ? nil : ::Protip::Wrapper.new(response, resource.class.transformer)
      end
      def self.collection(resource_class, action, method, message, response_type)
        response = resource_class.client.request path: "#{resource_class.base_path}/#{action}",
          method: method,
          message: message,
          response_type: response_type
        nil == response ? nil : ::Protip::Wrapper.new(response, resource_class.transformer)
      end
    end
  end
end
