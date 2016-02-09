require 'protip/transformer'

module Protip
  module Transformer
    # Simple wrapper to allow combining the behavior of multiple transformers.
    class DelegatingTransformer
      include Protip::Transformer
      def initialize
        @transformers = []
      end

      # Add a transformer to the front of the stack, e.g. it will be used before any
      # already-present transformers if a message class is transformable by more than
      # one of them.
      def add(transformer)
        @transformers.unshift transformer
      end

      def transformable?(message_class)
        @transformers.any?{|t| t.convertible? message_class}
      end

      def to_object(message)
        @transformers.detect{|t| t.convertible? message.class}.to_object(message)
      end

      def to_message(object, message_class)
        @transformers.detect{|t| t.convertible? message_class}.to_message(object, message_class)
      end
    end
  end
end