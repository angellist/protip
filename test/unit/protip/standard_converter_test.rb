require 'test_helper'

require 'google/protobuf/wrappers'
require 'protip/standard_converter'

describe Protip::StandardConverter do
  let(:converter) { Protip::StandardConverter.new }

  let(:integer_types) do
    [Google::Protobuf::Int64Value, Google::Protobuf::Int32Value, Google::Protobuf::UInt64Value, Google::Protobuf::UInt32Value]
  end

  let(:float_types) do
    [Google::Protobuf::FloatValue, Google::Protobuf::DoubleValue]
  end

  let(:bool_types) do
    [Google::Protobuf::BoolValue]
  end

  let(:string_types) do
    [Google::Protobuf::StringValue]
  end

  let(:bytes_types) do
    [Google::Protobuf::BytesValue]
  end


  describe '#convertible?' do
    it 'converts all standard types' do
      (integer_types + float_types + string_types + bool_types + [Protip::Messages::Date]).each do |message_class|
        assert converter.convertible?(message_class), "expected type #{message_class.descriptor.name} not convertible"
      end
    end

    it 'does not convert other message types' do
      pool = Google::Protobuf::DescriptorPool.new
      pool.build { add_message('test_message') { optional :id, :string, 1 } }
      refute converter.convertible?(pool.lookup('test_message').msgclass)
    end
  end

  describe '#to_object' do
    it 'converts wrapper types' do
      {
        6                                                 => integer_types,
        5.5                                               => float_types,
        false                                             => bool_types,
        'asdf'                                            => string_types,
        Base64.decode64("U2VuZCByZWluZm9yY2VtZW50cw==\n") => bytes_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal value, converter.to_object(message_class.new value: value)
        end
      end
    end

    it 'converts dates' do
      date = converter.to_object(::Protip::Messages::Date.new year: 2015, month: 2, day: 9)
      assert_instance_of ::Date, date
      assert_equal '2015-02-09', date.strftime
    end
  end

  describe '#to_message' do
    it 'converts wrapper types' do
      {
        6                                                 => integer_types,
        5.5                                               => float_types,
        false                                             => bool_types,
        'asdf'                                            => string_types,
        Base64.decode64("U2VuZCByZWluZm9yY2VtZW50cw==\n") => bytes_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(value: value), converter.to_message(value, message_class)
        end
      end
    end

    it 'converts dates' do
      date = ::Date.new(2012, 5, 7)
      assert_equal 7, date.day # Sanity check argument order
      assert_equal ::Protip::Messages::Date.new(year: 2012, month: 5, day: 7), converter.to_message(date, ::Protip::Messages::Date)
    end

    it 'converts truthy values to booleans' do
      [true, 1, '1', 't', 'T', 'true', 'TRUE'].each do |truth_value|
        assert_equal Google::Protobuf::BoolValue.new(value: true),
                     converter.to_message(truth_value, Google::Protobuf::BoolValue)
      end
    end

    it 'converts falsey values to booleans' do
      [nil, false, 0, '0', 'f', 'F', 'false', 'FALSE'].each do |false_value|
        assert_equal Google::Protobuf::BoolValue.new(value: false),
                     converter.to_message(false_value, Google::Protobuf::BoolValue)
      end
    end

    it 'raises an exception if non-boolean values passed to boolean field' do
      ['test', Object.new, 2, {}, []].each do |bad_value|
        assert_raises TypeError do
          converter.to_message(bad_value, Google::Protobuf::BoolValue)
        end
      end
    end

  end
end