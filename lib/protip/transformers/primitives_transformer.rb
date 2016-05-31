require 'protip/transformer'

require 'protip/transformers/delegating_transformer'

module Protip
  module Transformers
    # Transforms ints, strings, booleans, floats, and bytes to/from their
    # well-known types (for scalars) and Protip repeated types.
    class PrimitivesTransformer < DelegatingTransformer
      TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE', 'on', 'ON']
      FALSE_VALUES = [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF']

      def initialize
        super
        {
          Int64:   :to_i.to_proc,
          Int32:   :to_i.to_proc,
          UInt64:  :to_i.to_proc,
          UInt32:  :to_i.to_proc,
          Double:  :to_f.to_proc,
          Float:   :to_f.to_proc,
          String:  :to_s.to_proc,
          Bool:    ->(object) { to_boolean(object) },
          Bytes:   ->(object) { object },
        }.each do |type, transform|
          self["google.protobuf.#{type}Value"] = ScalarTransformer.new(transform)
          self["protip.messages.Repeated#{type}"] = ArrayTransformer.new(transform)
        end          
      end

      private
      def to_boolean(object)
        return true if TRUE_VALUES.include?(object)
        return false if FALSE_VALUES.include?(object)

        object
      end

      # Helper transfomer for scalar well-known types.
      class ScalarTransformer
        # @param [Proc] transform Proc to convert a Ruby object to the
        #   primitive type that we're transforming to.
        def initialize(transform)
          @transform = transform
        end

        def to_object(message, field)
          message.value
        end

        def to_message(object, field)
          value = @transform[object]
          field.subtype.msgclass.new(value: value)
        end
      end
      private_constant :ScalarTransformer

      # Helper transformer for repeated types.
      class ArrayTransformer
        def initialize(transform)
          @transform = transform
        end

        def to_object(message, field)
          message.values.to_a.freeze
        end

        def to_message(object, field)
          values = (object.is_a?(::Enumerable) ? object : [object]).map do |value|
            @transform[value]
          end
          field.subtype.msgclass.new(values: values)
        end
      end
      private_constant :ArrayTransformer
    end
  end
end
