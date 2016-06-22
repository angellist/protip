require 'test_helper'
require 'protip/transformers/big_decimal_transformer'

require 'protip/messages'

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
    def self.it_transforms(name, value)
      it "transforms #{name} values" do
        message = transformer.to_message(value, field)
        assert_equal value, transformer.to_object(message, field)
      end
    end
    it_transforms 'integer', BigDecimal.new(104, 1)
    it_transforms 'infinity', (BigDecimal.new(1, 1) / 0)
    it_transforms 'fractions', BigDecimal.new(100.5, 5)
    it_transforms 'rational numbers', BigDecimal.new(Rational(2, 3), 3)
  end
end