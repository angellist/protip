require 'protip/transformers/delegating_transformer'

module Protip
  module Transformers
    class EnumTransformer < DelegatingTransformer
      def initialize
        super
        self['protip.messages.EnumValue'] = ScalarTransformer.new
        self['protip.messages.RepeatedEnum'] = ArrayTransformer.new
      end

      def self.enum_for_field(field)
        Google::Protobuf::DescriptorPool.generated_pool.lookup(field.instance_variable_get(:'@_protip_enum_value'))
      end

      # Internal helper classes - under the hood we use separate transformers for
      # the scalar and repeated cases, and both of them share transformation logic
      # by inheriting from +SingleMessageEnumTransformer+.
      class SingleMessageEnumTransformer
        include Protip::Transformer
        private
        # Instance-level cached version of the class method above
        def enum_for_field(field)
          @enum_for_field_cache ||= {}
          name = EnumTransformer.enum_for_field(field)
          @enum_for_field_cache[name] ||= EnumTransformer.enum_for_field(field)

          @enum_for_field_cache[name] ||
            raise("protip_enum missing or invalid for field '#{field.name}'")
        end

        # Matches the protobuf enum setter behavior.
        # Convert +:VALUE+ or +5+ to their corresponding enum integer value.
        # @example
        #   // foo.proto
        #   enum Foo {
        #     BAR = 0;
        #     BAZ = 1;
        #   }
        #   // ScalarTransformer.to_int(:BAZ) # => 1
        #   // ScalarTransformer.to_int(4) # => 4
        def to_int(symbol_or_int, field)
          if symbol_or_int.is_a?(Fixnum)
            symbol_or_int
          else
            # Convert +.to_sym+ explicitly to allow strings (or other
            # symobolizable objects) to be passed in to setters.
            enum_for_field(field).lookup_name(symbol_or_int.to_sym) ||
              raise(RangeError.new "unknown symbol value for field '#{field.name}'")
          end
        end

        # Matches the protobuf enum getter behavior.
        # Convert integers to their associated enum symbol, or pass them
        # through if the
        def to_symbol_or_int(int, field)
          enum = EnumTransformer.enum_for_field(field) ||
            raise("protip_enum missing or invalid for field '#{field.name}'")
          enum.lookup_value(int) || int
        end
      end
      private_constant :SingleMessageEnumTransformer

      # For +protip.messages.EnumValue+
      class ScalarTransformer < SingleMessageEnumTransformer
        def to_object(message, field)
          to_symbol_or_int(message.value, field)
        end
        def to_message(object, field)
          field.subtype.msgclass.new(value: to_int(object, field))
        end
      end
      private_constant :ScalarTransformer

      # For +protip.messages.RepeatedEnum+
      class ArrayTransformer < SingleMessageEnumTransformer
        def to_object(message, field)
          message.values.map do |value|
            to_symbol_or_int(value, field)
          end
        end

        def to_message(object, field)
          values = (object.is_a?(::Enumerable) ? object : [object]).map do |value|
            to_int(value, field)
          end
          field.subtype.msgclass.new(values: values)
        end
      end
      private_constant :ArrayTransformer
    end
  end
end
