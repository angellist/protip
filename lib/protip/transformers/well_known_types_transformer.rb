require 'protip/transformer'

module Protip
  module Transformers
    class WellKnownTypesTransformer
      include Protip::Transformer

      TYPES = %w(Boolean Int64 Int32 UInt64 UInt32 Double Float String Bytes).map{|type| "google.protobuf.#{type}Value"}

      def transformable?(message_class)
        TYPES.include?(message_class.descriptor.name)
      end

      def to_object(message)
        message.value
      end

      def to_message(object, message_class)
        message_class.new value: object
      end
    end
  end
end