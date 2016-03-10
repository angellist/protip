require 'money'

require 'active_support/time_with_zone'

require 'protip/converter'

require 'protip/messages/currency'
require 'protip/messages/money'
require 'protip/messages/range'
require 'protip/messages/repeated_wrappers'
require 'protip/messages/types'
require 'protip/messages/wrappers'
require 'google/protobuf'
module Protip
  class StandardConverter
    include Protip::Converter

    TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE', 'on', 'ON']
    FALSE_VALUES = [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF']

    class << self
      attr_reader :conversions
    end
    @conversions = {}

    ## Protip types
    @conversions['protip.messages.Currency'] = {
      to_object: ->(message, field) { message.currency_code },
      to_message: ->(currency_code, message_class, field) { message_class.new currency_code: currency_code }
    }

    @conversions['protip.messages.Money'] = {
      to_object: ->(message, field) do
        ::Money.new(message.amount_cents, message.currency.currency_code)
      end,
      to_message: ->(money, message_class, field) do
        raise ArgumentError unless money.is_a?(::Money)
        currency = ::Protip::Messages::Currency.new(currency_code: money.currency.iso_code.to_sym)
        message_class.new(
          amount_cents: money.fractional,
          currency: currency
        )
      end
    }

    @conversions['protip.messages.Date'] = {
      to_object: ->(message, field) { ::Date.new(message.year, message.month, message.day) },
      to_message: lambda do |date, message_class, field|
        raise ArgumentError unless date.is_a?(::Date)
        message_class.new year: date.year, month: date.month, day: date.day
      end
    }

    @conversions['protip.messages.Range'] = {
      to_object: ->(message, field) { message.begin..message.end },
      to_message: ->(range, message_class, field) do
        message_class.new(begin: range.begin.to_i, end: range.end.to_i)
      end
    }

    ## Standard wrappers
    %w(Int64 Int32 UInt64 UInt32 Double Float String Bytes).each do |type|
      @conversions["google.protobuf.#{type}Value"] = {
        to_object: ->(message, field) { message.value },
        to_message: lambda do |value, message_class, field|
          message_class.new value: value
        end
      }
      @conversions["protip.messages.Repeated#{type}"] = {
        to_object: ->(message, field) { message.values.to_a.freeze },
        to_message: lambda do |value, message_class, field|
          message_class.new values: (value.is_a?(Enumerable) ? value : [value])
        end
      }
    end

    conversions['google.protobuf.BoolValue'] = {
      to_object: ->(message, field) { message.value },
      to_message: lambda do |value, message_class, field|
        message_class.new value: value_to_boolean(value)
      end
    }

    conversions['protip.messages.RepeatedBool'] = {
      to_object: ->(message, field) { message.values.to_a.freeze },
      to_message: lambda do |value, message_class, field|
        message_class.new values: (value.is_a?(Enumerable) ? value : [value]).map{|v| value_to_boolean(v)}
      end

    }

    conversions['protip.messages.EnumValue'] = {
      to_object: lambda do |message, field|
        enum_for_field(field).lookup_value(message.value) || message.value
      end,
      to_message: lambda do |value, message_class, field|
        enum_value = (value.is_a?(Fixnum) ? value : enum_for_field(field).lookup_name(value.to_sym))
        if nil == enum_value
          raise RangeError.new('Unknown symbol value for an EnumValue field.')
        end
        message_class.new(value: enum_value)
      end
    }

    conversions['protip.messages.RepeatedEnum'] = {
      to_object: lambda do |message, field|
        enum = enum_for_field(field)
        message.values.map{|v| enum.lookup_value(v) || v}
      end,
      to_message: lambda do |values, message_class, field|
        enum = nil # Don't look this up unless we have to
        (values = [values]) unless values.is_a?(Enumerable) # Convert to an array if a scalar was given
        # Convert values in the same way we do for +protip.messages.EnumValue+
        message_class.new values: (values.map do |value|
          if value.is_a?(Fixnum)
            value
          else
            enum ||= enum_for_field(field)
            enum.lookup_name(value.to_sym) || (raise RangeError.new('Unknown symbol value for a RepeatedEnum field.'))
          end
        end)
      end
    }

    ## ActiveSupport objects
    conversions['protip.messages.ActiveSupport.TimeWithZone'] = {
      to_object: ->(message, field) {
        ActiveSupport::TimeWithZone.new(
          Time.at(message.utc_timestamp).utc,
          ActiveSupport::TimeZone.new(message.time_zone_name)
        )
      },
      to_message: ->(value, message_class, field) {
        if !value.is_a?(::ActiveSupport::TimeWithZone) && (value.is_a?(Time) || value.is_a?(DateTime))
          value = ::ActiveSupport::TimeWithZone.new(value.to_time.utc, ::ActiveSupport::TimeZone.new('UTC'))
        end
        raise ArgumentError unless value.is_a?(::ActiveSupport::TimeWithZone)

        message_class.new(
          utc_timestamp: value.to_i,
          time_zone_name: value.time_zone.name,
        )
      }
    }

    def convertible?(message_class)
      self.class.conversions.has_key?(message_class.descriptor.name)
    end

    def to_object(message, field)
      self.class.conversions[message.class.descriptor.name][:to_object].call(message, field)
    end

    def to_message(object, message_class, field)
      self.class.conversions[message_class.descriptor.name][:to_message].call(object, message_class, field)
    end

    class << self
      # Similar to Rails 3 value_to_boolean
      def value_to_boolean(value)
        return true if TRUE_VALUES.include?(value)
        return false if FALSE_VALUES.include?(value)
        # If we don't get a truthy/falsey value, use the original value (which should raise an
        # exception)
        value
      end

      private
      def enum_for_field(field)
        Google::Protobuf::DescriptorPool.generated_pool.lookup(field.instance_variable_get(:'@_protip_enum_value'))
      end
    end
  end
end