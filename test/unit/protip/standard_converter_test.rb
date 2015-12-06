require 'test_helper'
require 'money'

require 'google/protobuf/wrappers'
require 'protip/standard_converter'

describe Protip::StandardConverter do
  let(:converter) { Protip::StandardConverter.new }

  let(:integer_types) do
    [
      Google::Protobuf::Int64Value,
      Google::Protobuf::Int32Value,
      Google::Protobuf::UInt64Value,
      Google::Protobuf::UInt32Value
    ]
  end

  let(:float_types) do
    [
      Google::Protobuf::FloatValue,
      Google::Protobuf::DoubleValue
    ]
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

  let(:protip_types) do
    [
      Protip::Messages::Range,
      Protip::Messages::Date,
      Protip::Messages::Money,
      Protip::Messages::Currency
    ]
  end

  describe '#convertible?' do
    it 'converts all standard types' do
      (integer_types + float_types + string_types + bool_types + protip_types).each do |message_class|
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

    it 'converts ranges' do
      range = converter.to_object(::Protip::Messages::Range.new begin: 1, end: 4)
      assert_instance_of ::Range, range
      assert_equal 1..4, range
    end

    it 'converts currency' do
      currency = converter.to_object(::Protip::Messages::Currency.new currency_code: :GBP)
      assert_equal :GBP, currency
    end

    it 'converts money' do
      message = ::Protip::Messages::Money.new amount_cents: 250,
                                              currency: (::Protip::Messages::Currency.new currency_code: :CAD)
      money = converter.to_object(message)
      assert_instance_of ::Money, money
      assert_equal Money::Currency.new(:CAD), money.currency
      assert_equal 250, money.fractional
      assert_equal ::Money.new(250, 'CAD'), money
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

    it 'converts ranges' do
      range = -1..34
      assert_equal ::Protip::Messages::Range.new(begin: -1, end: 34), converter.to_message(range, ::Protip::Messages::Range)
    end

    it 'converts currency' do
      currency = :HKD
      message = converter.to_message(currency, ::Protip::Messages::Currency)
      assert_equal ::Protip::Messages::Currency.new(currency_code: currency), message
    end

    it 'converts money' do
      money = ::Money.new(250, 'CAD')
      message = converter.to_message(money, ::Protip::Messages::Money)
      assert_instance_of ::Protip::Messages::Money, message
      assert_equal ::Protip::Messages::Money.new(
                     amount_cents: money.cents,
                     currency: ::Protip::Messages::Currency.new(
                       currency_code: money.currency.iso_code.to_sym
                     )),
                   message
    end

    it 'converts truthy values to booleans' do
      [true, 1, '1', 't', 'T', 'true', 'TRUE', 'on', 'ON'].each do |truth_value|
        assert_equal Google::Protobuf::BoolValue.new(value: true),
                     converter.to_message(truth_value, Google::Protobuf::BoolValue)
      end
    end

    it 'converts falsey values to booleans' do
      [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF'].each do |false_value|
        assert_equal Google::Protobuf::BoolValue.new(value: false),
                     converter.to_message(false_value, Google::Protobuf::BoolValue)
      end
    end

    it 'raises an exception if non-boolean values passed to boolean field' do
      [nil, 'test', Object.new, 2, {}, []].each do |bad_value|
        assert_raises TypeError do
          converter.to_message(bad_value, Google::Protobuf::BoolValue)
        end
      end
    end
  end
end