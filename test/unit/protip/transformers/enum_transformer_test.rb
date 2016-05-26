require 'test_helper'

require 'protip/transformers/enum_transformer'

require 'protip/messages'

describe Protip::Transformers::EnumTransformer do
  let(:transformer) { Protip::Transformers::EnumTransformer.new }
  let(:pool) do
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
  let(:message_class) { raise NotImplementedError } # sub-sections must define
  let(:field) do
    field = mock.responds_like_instance_of ::Google::Protobuf::FieldDescriptor
    field.stubs(:submsg_name).returns(message_class.descriptor.name)
    field.stubs(:subtype).returns(message_class.descriptor)
    field
  end

  before do
    Protip::Transformers::EnumTransformer.stubs(:enum_for_field).
      returns(enum)
  end

  describe '#to_object' do
    describe 'scalars' do
      let(:message_class) { Protip::Messages::EnumValue }
      it 'transforms enum values in range to symbols' do
        message = message_class.new(value: 1)
        assert_equal :ONE, transformer.to_object(message, field)
      end
      it 'transforms enum values out of range to integers' do
        message = message_class.new(value: 5)
        assert_equal 5, transformer.to_object(message, field)
      end
    end
    describe 'arrays' do
      let(:message_class) { Protip::Messages::RepeatedEnum }
      it 'transforms repeated enum values in range to symbols' do
        message = message_class.new(values: [0, 1])
        assert_equal [:ZERO, :ONE], transformer.to_object(message, field)
      end
      it 'transforms repeated enum values out of range to integers' do
        message = message_class.new(values: [3, 1, 5])
        assert_equal [3, :ONE, 5], transformer.to_object(message, field)
      end
    end
  end

  describe '#to_message' do
    %w(zero one two).each do |number| # values symbolizing as :ZERO, :ONE, :TWO
      let number do
        value = mock
        value.stubs(:to_sym).returns(number.upcase.to_sym)
        value
      end
    end

    describe 'scalars' do
      let(:message_class) { Protip::Messages::EnumValue }
      it 'transforms integers to messages' do
        assert_equal message_class.new(value: 1), transformer.to_message(1, field)
      end
      it 'transforms non-integers via :to_sym' do
        assert_equal message_class.new(value: 1), transformer.to_message(one, field)
      end
      it 'throws an error when an out-of-range symbol is given' do
        field.stubs(:name).returns('FOO') # The exception message contains this
        exception = assert_raises RangeError do
          transformer.to_message(two, field)
        end
        assert_match(/FOO/, exception.message)
      end
    end

    describe 'arrays' do
      let(:message_class) { Protip::Messages::RepeatedEnum }
      it 'transforms integers' do
        assert_equal message_class.new(values: [1, 4]),
          transformer.to_message([1, 4], field)
      end
      it 'transforms non-integers via :to_sym' do
        assert_equal message_class.new(values: [0, 2, 1]),
          transformer.to_message([zero, 2, one], field)
      end
      it 'throws an error when an out-of-range symbol is given' do
        field.stubs(:name).returns('FOO') # The exception message contains this
        exception = assert_raises RangeError do
          transformer.to_message([0, two], field)
        end
        assert_match(/FOO/, exception.message)
      end
      it 'allows assigning a scalar value' do
        assert_equal message_class.new(values: [1]), transformer.to_message(one, field)
      end
    end

  end

  describe '.enum_for_field' do
    # TODO pending https://github.com/google/protobuf/issues/1198
  end

  if false #describe '(functional)' do # Temp - test an actual compiled file to make sure our options hack is working
    require 'protip/messages/test'
    require 'protip/wrapper'
    let(:wrapped_message) { Protip::Messages::EnumTest.new }
    let(:wrapper) { Protip::Wrapper.new wrapped_message, transformer }

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
