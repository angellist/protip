require 'test_helper'
require 'money'

require 'google/protobuf/wrappers'
require 'protip/messages/active_support/time_with_zone'
#require 'protip/standard_converter'
require 'protip/messages/test'

if false #describe Protip::StandardConverter do
  let :pool do
    # See https://github.com/google/protobuf/blob/master/ruby/tests/generated_code.rb for
    # examples of field types you can add here
    pool = Google::Protobuf::DescriptorPool.new
    pool.build do
      add_enum 'number' do
        value :ZERO, 0
        value :ONE, 1
      end
    end
    pool
  end
  let(:enum) { pool.lookup 'number' }

  let(:transformer) { Protip::StandardConverter.new }

  let(:integer_types) do
    [
      Google::Protobuf::Int64Value,
      Google::Protobuf::Int32Value,
      Google::Protobuf::UInt64Value,
      Google::Protobuf::UInt32Value
    ]
  end

  let(:repeated_integer_types) do
    [
      Protip::Messages::RepeatedInt64,
      Protip::Messages::RepeatedInt32,
      Protip::Messages::RepeatedUInt64,
      Protip::Messages::RepeatedUInt32,
    ]
  end

  let(:float_types) do
    [
      Google::Protobuf::FloatValue,
      Google::Protobuf::DoubleValue
    ]
  end

  let(:repeated_float_types) do
    [
      Protip::Messages::RepeatedFloat,
      Protip::Messages::RepeatedDouble,
    ]
  end

  let(:bool_types) do
    [Google::Protobuf::BoolValue]
  end

  let(:repeated_bool_types) do
    [Protip::Messages::RepeatedBool]
  end

  let(:string_types) do
    [Google::Protobuf::StringValue]
  end

  let(:repeated_string_types) do
    [Protip::Messages::RepeatedString]
  end

  let(:bytes_types) do
    [Google::Protobuf::BytesValue]
  end

  let(:repeated_bytes_types) do
    [Protip::Messages::RepeatedBytes]
  end

  let(:protip_types) do
    [
      Protip::Messages::Range,
      Protip::Messages::Date,
      Protip::Messages::Money,
      Protip::Messages::Currency
    ]
  end

  let(:integer_value) { 6 }
  let(:float_value) { 5.5 }
  let(:bool_value) { true }
  let(:string_value) { 'asdf' }
  let(:bytes_value) { Base64.decode64("U2VuZCByZWluZm9yY2VtZW50cw==\n") }

  let(:field) { mock.responds_like_instance_of Google::Protobuf::FieldDescriptor }

  describe '(enums - functional)' do # Temp - test an actual compiled file to make sure our options hack is working
    let(:wrapped_message) { Protip::Messages::EnumTest.new }
    let(:wrapper) { Protip::Wrapper.new wrapped_message, converter }

    let(:value_map) do
      {
        :ONE => :ONE,
        1 => :ONE,
        2 => 2,
      }
    end

    it 'allows setting and getting a scalar field by Ruby value' do
      value_map.each do |value, expected|
        wrapper.enum = value
        assert_equal expected, wrapper.enum
      end
      assert_raises RangeError do
        wrapper.enum = :TWO
      end
    end
    it 'allows setting and getting a scalar field by message' do
      wrapper.enum = ::Protip::Messages::EnumValue.new(value: 1)
      assert_equal :ONE, wrapper.enum
    end

    it 'allows setting and getting a repeated field by Ruby value' do
      value_map.each do |value, expected|
        wrapper.repeated_enums = [value]
        assert_equal [expected], wrapper.repeated_enums
      end
      assert_raises RangeError do
        wrapper.repeated_enums = [:TWO]
      end
    end
    it 'allows setting and geting a repeated field by message' do
      wrapper.repeated_enums = ::Protip::Messages::RepeatedEnum.new(values: [2])
      assert_equal [2], wrapper.repeated_enums
    end


  end

end
