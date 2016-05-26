require 'protip/transformer'

module Protip
  module Transformers
    # A transformer which wraps all messages, passing in another
    # transformer (generally a "parent" delegating transformer with this
    # as its fallback) to the generated wrappers.
    class WrappingTransformer
      include Protip::Transformer
      def initialize(transformer)
        @transformer = transformer
      end

      def to_object(message, field)

      end

      def to_message(object, field)
      end
    end
  end
end
