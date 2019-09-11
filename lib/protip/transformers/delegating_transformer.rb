require 'protip/transformer'
require 'protip/transformers/abstract_transformer'
require 'forwardable'

module Protip
  module Transformers
    # A transformer which forwards to other transformers based on the message type
    # being converted.
    class DelegatingTransformer
      include Protip::Transformer
      extend Forwardable

      # @param [Protip::Transformer] fallback_transformer The transformer to use
      #   for messages that don't have a registered transformer already.
      # @param [Hash<String, Protip::Transformer>] transformers A message_name => transformer
      #   hash specifying which transformers to use for which message types.
      def initialize(fallback_transformer = AbstractTransformer.new, transformers = {})
        @fallback_transformer = fallback_transformer
        @transformers = transformers.dup
      end

      def_delegators :@transformers, :[]=, :[], :keys

      def merge!(delegating_transformer)
        delegating_transformer.keys.each do |key|
          self[key] = delegating_transformer[key]
        end
      end

      def to_object(message, field)
        transformer_for(field.submsg_name).to_object(message, field)
      end

      def to_message(object, field)
        transformer_for(field.submsg_name).to_message(object, field)
      end

      private

      def transformer_for(message_name)
        @transformers[message_name] || @fallback_transformer
      end
    end
  end
end
