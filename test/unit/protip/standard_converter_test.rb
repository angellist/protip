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

  describe '#convertible?' do
    it 'converts all standard types' do
      (integer_types + float_types + string_types + bool_types + protip_types + repeated_integer_types +
        repeated_float_types + repeated_string_types + repeated_bool_types).each do |message_class|
        assert converter.convertible?(message_class), "expected type #{message_class.descriptor.name} not convertible"
      end
    end

    it 'does not convert other message types' do
      pool = Google::Protobuf::DescriptorPool.new
      pool.build { add_message('test_message') { optional :id, :string, 1 } }
      refute converter.convertible?(pool.lookup('test_message').msgclass)
    end
  end

  let(:field) { mock.responds_like_instance_of Google::Protobuf::FieldDescriptor }

  describe '#to_object' do
    it 'converts wrapper types' do
      {
        integer_value => integer_types,
        float_value   => float_types,
        bool_value    => bool_types,
        string_value  => string_types,
        bytes_value   => bytes_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal value, converter.to_object(message_class.new(value: value), field)
        end
      end
    end

    it 'converts repeated types to an immutable array' do
      {
        integer_value => repeated_integer_types,
        float_value   => repeated_float_types,
        bool_value    => repeated_bool_types,
        string_value  => repeated_string_types,
        bytes_value   => repeated_bytes_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          result = converter.to_object(message_class.new(values: [value]), field)
          assert_equal [value], result
          exception = assert_raises RuntimeError do
            result << value
          end
          assert_equal 'can\'t modify frozen Array', exception.message
        end
      end
    end

    it 'converts dates' do
      date = converter.to_object(::Protip::Messages::Date.new(year: 2015, month: 2, day: 9), field)
      assert_instance_of ::Date, date
      assert_equal '2015-02-09', date.strftime
    end

    it 'converts ranges' do
      range = converter.to_object(::Protip::Messages::Range.new(begin: 1, end: 4), field)
      assert_instance_of ::Range, range
      assert_equal 1..4, range
    end

    it 'converts currency' do
      currency = converter.to_object(::Protip::Messages::Currency.new(currency_code: :GBP), field)
      assert_equal :GBP, currency
    end

    it 'converts money' do
      message = ::Protip::Messages::Money.new amount_cents: 250,
                                              currency: (::Protip::Messages::Currency.new currency_code: :CAD)
      money = converter.to_object(message, field)
      assert_instance_of ::Money, money
      assert_equal Money::Currency.new(:CAD), money.currency
      assert_equal 250, money.fractional
      assert_equal ::Money.new(250, 'CAD'), money
    end

    it 'converts times with zones' do
      message = ::Protip::Messages::ActiveSupport::TimeWithZone.new utc_timestamp: 1451610000,
                                                                    time_zone_name: 'America/Los_Angeles'
      time = converter.to_object(message, field)
      assert_instance_of ::ActiveSupport::TimeWithZone, time
      assert_equal 1451610000, time.to_i
      assert_equal '2015-12-31T17:00:00-08:00', time.iso8601
    end

    describe 'enums' do
      before do
        ::Protip::StandardConverter.stubs(:enum_for_field).with(field).returns(enum)
      end

      # Make sure we mirror the behavior of an actual enum field on the message.
      it 'converts enum values in range to symbols' do
        message = ::Protip::Messages::EnumValue.new value: 1
        assert_equal :ONE, converter.to_object(message, field)
      end

      it 'converts enum values out of range to integers' do
        message = ::Protip::Messages::EnumValue.new value: 5
        assert_equal 5, converter.to_object(message, field)
      end

      it 'converts repeated enum values in range to symbols' do
        message = ::Protip::Messages::RepeatedEnum.new values: [0, 1]
        assert_equal [:ZERO, :ONE], converter.to_object(message, field)
      end

      it 'converts repeated enum values out of range to integers' do
        message = ::Protip::Messages::RepeatedEnum.new values: [3, 1, 5]
        assert_equal [3, :ONE, 5], converter.to_object(message, field)
      end
    end
  end

  describe '.enum_for_field' do
    # TODO pending https://github.com/google/protobuf/issues/1198
  end

  describe '#to_message' do
    it 'converts wrapper types' do
      {
        integer_value => integer_types,
        float_value   => float_types,
        bool_value    => bool_types,
        string_value  => string_types,
        bytes_value   => bytes_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(value: value), converter.to_message(value, message_class, field)
        end
      end
    end

    it 'converts wrapper types when set as a non-native type' do
      # Convert from string
      {
        integer_value => integer_types,
        float_value   => float_types,
        bool_value    => bool_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(value: value), converter.to_message(value.to_s, message_class, field)
        end
      end

      # Convert from integer
      {
        '4' => string_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(value: value), converter.to_message(value.to_i, message_class, field)
        end
      end
    end

    it 'converts repeated types when set with a scalar value' do
      {
        integer_value => repeated_integer_types,
        float_value   => repeated_float_types,
        bool_value    => repeated_bool_types,
        string_value  => repeated_string_types,
        bytes_value   => repeated_bytes_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(values: [value]), converter.to_message(value, message_class, field)
        end
      end
    end

    it 'converts repeated types when set with a non-native scalar type' do
      # Convert from string
      {
        integer_value => repeated_integer_types,
        float_value   => repeated_float_types,
        bool_value    => repeated_bool_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(values: [value]), converter.to_message(value.to_s, message_class, field)
        end
      end

      # Convert from integer
      {
        '4' => repeated_string_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(values: [value]), converter.to_message(value.to_i, message_class, field)
        end
      end

    end

    it 'converts repeated types when set with an enumerable value' do
      {
        integer_value => repeated_integer_types,
        float_value   => repeated_float_types,
        bool_value    => repeated_bool_types,
        string_value  => repeated_string_types,
        bytes_value   => repeated_bytes_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(values: [value, value]), converter.to_message(
            [value, value], message_class, field
          )
        end
      end
    end

    it 'converts repeated types when set with a non-native enumerable type' do
      # Convert from string
      {
        integer_value => repeated_integer_types,
        float_value   => repeated_float_types,
        bool_value    => repeated_bool_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(values: [value, value]), converter.to_message(
            [value.to_s, value.to_s], message_class, field
          )
        end
      end

      # Convert from integer
      {
        '4' => repeated_string_types,
      }.each do |value, message_types|
        message_types.each do |message_class|
          assert_equal message_class.new(values: [value, value]), converter.to_message(
            [value.to_i, value.to_i], message_class, field
          )
        end
      end

    end

    it 'converts dates' do
      date = ::Date.new(2012, 5, 7)
      assert_equal 7, date.day # Sanity check argument order
      assert_equal ::Protip::Messages::Date.new(year: 2012, month: 5, day: 7), converter.to_message(date, ::Protip::Messages::Date, field)
    end

    it 'converts ranges' do
      range = -1..34
      assert_equal ::Protip::Messages::Range.new(begin: -1, end: 34), converter.to_message(range, ::Protip::Messages::Range, field)
    end

    it 'converts currency' do
      currency = :HKD
      message = converter.to_message(currency, ::Protip::Messages::Currency, field)
      assert_equal ::Protip::Messages::Currency.new(currency_code: currency), message
    end

    it 'converts money' do
      money = ::Money.new(250, 'CAD')
      message = converter.to_message(money, ::Protip::Messages::Money, field)
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
                     converter.to_message(truth_value, Google::Protobuf::BoolValue, field)
      end
    end

    it 'converts falsey values to booleans' do
      [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF'].each do |false_value|
        assert_equal Google::Protobuf::BoolValue.new(value: false),
                     converter.to_message(false_value, Google::Protobuf::BoolValue, field)
      end
    end

    it 'raises an exception if non-boolean values passed to boolean field' do
      [nil, 'test', Object.new, 2, {}, []].each do |bad_value|
        assert_raises TypeError do
          converter.to_message(bad_value, Google::Protobuf::BoolValue, field)
        end
      end
    end

    it 'converts times with zones' do
      time_with_zone = ::ActiveSupport::TimeWithZone.new(Time.new(2016, 1, 1, 0, 0, 0, 0),
        ::ActiveSupport::TimeZone.new('America/New_York'))
      message = converter.to_message(time_with_zone, ::Protip::Messages::ActiveSupport::TimeWithZone, field)
      assert_equal 1451606400, message.utc_timestamp
      assert_equal 'America/New_York', message.time_zone_name
    end

    it 'converts times without zones' do
      time = Time.new(2016, 1, 1, 0, 0, 0, -3600)
      message = converter.to_message(time, ::Protip::Messages::ActiveSupport::TimeWithZone, field)
      assert_equal 1451610000, message.utc_timestamp
      assert_equal 'UTC', message.time_zone_name
    end

    it 'converts datetimes without zones' do
      datetime = DateTime.new(2016, 1, 1, 0, 0, 0, '-1')
      message = converter.to_message(datetime, ::Protip::Messages::ActiveSupport::TimeWithZone, field)
      assert_equal 1451610000, message.utc_timestamp
      assert_equal 'UTC', message.time_zone_name

    end

    describe 'enums' do
      before do
        ::Protip::StandardConverter.stubs(:enum_for_field).with(field).returns(enum)
      end
      def convert(value)
        converter.to_message value, message_class, field
      end
      %w(zero one two).each do |number| # values symbolizing as :ZERO, :ONE, :TWO
        let number do
          value = mock
          value.stubs(:to_sym).returns(number.upcase.to_sym)
          value
        end
      end

      describe '::Protip::Messages::EnumValue' do
        let(:message_class) { ::Protip::Messages::EnumValue }
        # Ensure identical behavior to setting a standard enum field
        it 'converts integers' do
          assert_equal 1, convert(1).value, 'improper conversion of an in-range integer'
          assert_equal 4, convert(4).value, 'improper conversion of an out-of-range integer'
        end
        it 'converts non-integers via to_sym' do
          assert_equal 1, convert(one).value, 'improper conversion of non-integer value'
        end
        it 'throws an error when a non-existent symbol is given' do
          assert_raises RangeError do
            convert(two)
          end
        end
      end

      describe '::Protip::Messages::RepeatedEnum' do
        let(:message_class) { ::Protip::Messages::RepeatedEnum }
        it 'converts integers' do
          assert_equal [1, 4], convert([1, 4]).values
        end
        it 'converts non-integers via to_sym' do
          assert_equal [0, 2, 1], convert([zero, 2, one]).values
        end
        it 'throws an error when a non-existent symbol is given' do
          assert_raises RangeError do
            convert([0, two])
          end
        end
        it 'allows assigning a scalar value' do
          assert_equal [1], convert(one).values
        end
      end
    end
  end

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
