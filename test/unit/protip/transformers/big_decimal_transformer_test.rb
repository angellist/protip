require 'test_helper'
require 'protip/transformers/big_decimal_transformer'

require 'protip/messages_pb'

describe Protip::Transformers::BigDecimalTransformer do
  let(:transformer) { Protip::Transformers::BigDecimalTransformer.new }
  let(:message_class) { Protip::Messages::BigDecimalValue }
  let(:field) do
    field = mock.responds_like_instance_of ::Google::Protobuf::FieldDescriptor
    field.stubs(:submsg_name).returns(message_class.descriptor.name)
    field.stubs(:subtype).returns(message_class.descriptor)
    field
  end

  # Since we're just serializing/deserializing values, we test both
  # transformer methods in tandem.
  describe 'transformation' do
    # Assumes expected_value = value unless it is explicitly provided
    def self.it_transforms(name, value, expected_value = nil)
      expected_value ||= value
      it "transforms #{name} values" do
        message = transformer.to_message(value, field)
        object = transformer.to_object(message, field)
        assert_equal BigDecimal, object.class
        assert_equal expected_value, object
      end
    end
    describe 'for BigDecimal arguments' do
      it_transforms 'integer', BigDecimal.new(104, 1)
      it_transforms 'fractions', BigDecimal.new(100.5, 5)
      it_transforms 'rational numbers', BigDecimal.new(Rational(2, 3), 3)
    end

    describe 'for non-BigDecimal arguments' do
      it_transforms 'integer', 3, BigDecimal.new(3, 1)
      it_transforms 'string', '3.3', BigDecimal.new(3.3, 2)

      # Match standard BigDecimal behavior for floats
      it 'raises an argument error for floats' do
        exception = assert_raises ArgumentError do
          transformer.to_message(5.5, field)
        end
        assert_equal "can't omit precision for a Float.", exception.message
      end
    end
  end
end
