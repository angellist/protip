require 'test_helper'

require 'protip/transformers/deprecated_transformer'

require 'protip/messages_pb'

describe Protip::Transformers::DeprecatedTransformer do
  let(:transformer) { Protip::Transformers::DeprecatedTransformer.new }
  let(:message_class) { raise NotImplementedError } # sub-sections must define
  let(:field) do
    field = mock.responds_like_instance_of ::Google::Protobuf::FieldDescriptor
    field.stubs(:submsg_name).returns(message_class.descriptor.name)
    field.stubs(:subtype).returns(message_class.descriptor)
    field
  end

  describe '#to_object' do
    describe 'Date' do
      let(:message_class) { Protip::Messages::Date }
      it 'converts dates' do
        date = transformer.to_object(message_class.new(year: 2015, month: 2, day: 9), field)
        assert_instance_of ::Date, date
        assert_equal '2015-02-09', date.strftime
      end
    end

    describe 'Range' do
      let(:message_class) { Protip::Messages::Range }
      it 'converts ranges' do
        range = transformer.to_object(message_class.new(begin: 1, end: 4), field)
        assert_instance_of ::Range, range
        assert_equal 1..4, range
      end
    end

    describe 'Currency' do
      let(:message_class) { Protip::Messages::Currency }
      it 'converts currency' do
        currency = transformer.to_object(message_class.new(currency_code: :GBP), field)
        assert_equal :GBP, currency
      end
    end

    describe 'Money' do
      let(:message_class) { Protip::Messages::Money }
      it 'converts money' do
        message = message_class.new amount_cents: 250,
          currency: (Protip::Messages::Currency.new currency_code: :CAD)
        money = transformer.to_object(message, field)
        assert_instance_of ::Money, money
        assert_equal ::Money::Currency.new(:CAD), money.currency
        assert_equal 250, money.fractional
        assert_equal ::Money.new(250, 'CAD'), money
      end
    end

    describe 'ActiveSupport::TimeWithZone' do
      let(:message_class) { Protip::Messages::ActiveSupport::TimeWithZone }
      it 'converts times with zones' do
        message = message_class.new utc_timestamp: 1451610000,
          time_zone_name: 'America/Los_Angeles'
        time = transformer.to_object(message, field)
        assert_instance_of ::ActiveSupport::TimeWithZone, time
        assert_equal 1451610000, time.to_i
        assert_equal '2015-12-31T17:00:00-08:00', time.iso8601
      end
    end
  end

  describe '#to_message' do
    describe 'Date' do
      let(:message_class) { Protip::Messages::Date }
      it 'converts dates' do
        date = ::Date.new(2012, 5, 7)
        assert_equal 7, date.day # Sanity check argument order
        assert_equal message_class.new(year: 2012, month: 5, day: 7),
          transformer.to_message(date, field)
      end
    end

    describe 'Range' do
      let(:message_class) { Protip::Messages::Range }
      it 'converts ranges' do
        range = -1..34
        assert_equal message_class.new(begin: -1, end: 34),
          transformer.to_message(range, field)
      end
    end

    describe 'Currency' do
      let(:message_class) { Protip::Messages::Currency }
      it 'converts currency' do
        currency = :HKD
        message = transformer.to_message(currency, field)
        assert_equal message_class.new(currency_code: currency), message
      end
    end

    describe 'Money' do
      let(:message_class) { Protip::Messages::Money }
      it 'converts money' do
        money = ::Money.new(250, 'CAD')
        message = transformer.to_message(money, field)
        assert_instance_of message_class, message
        assert_equal message_class.new(
          amount_cents: money.cents,
          currency: Protip::Messages::Currency.new(
            currency_code: money.currency.iso_code.to_sym
          )),
          message
      end

      it 'converts other objects via #to_money' do
        obj = mock
        obj.stubs(:to_money).returns ::Money.new(250, 'CAD')
        message = transformer.to_message(obj, field)
        assert_equal message_class.new(
          amount_cents: 250,
          currency: Protip::Messages::Currency.new(
            currency_code: :CAD
          )),
          message
      end
    end

    describe 'ActiveSupport::TimeWithZone' do
      let(:message_class) { Protip::Messages::ActiveSupport::TimeWithZone }
      it 'converts times with zones' do
        time_with_zone = ::ActiveSupport::TimeWithZone.new(Time.new(2016, 1, 1, 0, 0, 0, 0),
          ::ActiveSupport::TimeZone.new('America/New_York'))
        message = transformer.to_message(time_with_zone, field)
        assert_equal 1451606400, message.utc_timestamp
        assert_equal 'America/New_York', message.time_zone_name
      end

      it 'converts times without zones' do
        time = ::Time.new(2016, 1, 1, 0, 0, 0, -3600)
        message = transformer.to_message(time, field)
        assert_equal 1451610000, message.utc_timestamp
        assert_equal 'UTC', message.time_zone_name
      end

      it 'converts datetimes without zones' do
        datetime = ::DateTime.new(2016, 1, 1, 0, 0, 0, '-1')
        message = transformer.to_message(datetime, field)
        assert_equal 1451610000, message.utc_timestamp
        assert_equal 'UTC', message.time_zone_name
      end
    end
  end
end
