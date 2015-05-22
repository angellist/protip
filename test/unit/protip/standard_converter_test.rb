require 'test_helper'

require 'protip/standard_converter'

describe Protip::StandardConverter do
  let(:converter) { Protip::StandardConverter.new }

  let(:integer_types) do
    [Protip::Int64Value, Protip::Int32Value, Protip::UInt64Value, Protip::UInt32Value]
  end

  let(:float_types) do
    [Protip::FloatValue, Protip::DoubleValue]
  end

  let(:bool_types) do
    [Protip::BoolValue]
  end

  let(:string_types) do
    [Protip::StringValue, Protip::BytesValue]
  end


  describe '#convertible?' do
    it 'converts all standard types' do
      (integer_types + float_types + string_types + bool_types + [Protip::Date]).each do |message_class|
        assert converter.convertible?(message_class), 'expected type not convertible'
      end
    end

    it 'does not convert other message types' do
      refute converter.convertible?(Class.new(::Protobuf::Message))
    end
  end

  describe '#to_object' do
    it 'converts wrapper types' do
      {
        6      => integer_types,
        5.5    => float_types,
        false  => bool_types,
        'asdf' => string_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal value, converter.to_object(message_class.new value: value)
        end
      end
    end

    it 'converts dates' do
      date = converter.to_object(Protip::Date.new year: 2015, month: 2, day: 9)
      assert_instance_of Date, date
      assert_equal 'Mon, 09 Feb 2015', date.inspect
    end
  end

  describe '#to_message' do
    it 'converts wrapper types' do
      {
        6      => integer_types,
        5.5    => float_types,
        false  => bool_types,
        'asdf' => string_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(value: value), converter.to_message(value, message_class)
        end
      end
    end

    it 'converts dates' do
      date = ::Date.new(2012, 5, 7)
      assert_equal 7, date.day # Sanity check argument order
      assert_equal Protip::Date.new(year: 2012, month: 5, day: 7), converter.to_message(date, Protip::Date)
    end
  end
end