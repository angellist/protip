require 'protip/decorator'
require 'protip/transformer'

module Protip
  module Transformers
    # A transformer which decorates all messages, passing in another
    # transformer (generally a "parent" delegating transformer with
    # this as its fallback) to the generated decorators. Allows
    # cascading message decoration.
    class DecoratingTransformer
      include Protip::Transformer
      def initialize(transformer)
        @transformer = transformer
      end

      def to_object(message, field)
        Protip::Decorator.new(message, @transformer)
      end

      def to_message(object, field)
        if object.is_a?(Protip::Decorator)
          object.message
        elsif object.is_a?(Hash)
          decorator = Protip::Decorator.new(field.subtype.msgclass.new, @transformer)
          decorator.assign_attributes(object)
          decorator.message
        else
          raise ArgumentError.new("#to_message expected a Hash or an already decorated object, received #{object.class.name} for #{field.type} #{field.name}")
        end
      end
    end
  end
end
