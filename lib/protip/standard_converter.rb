require 'protip/converter'

require 'protip/messages/range'
require 'protip/messages/types'
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
    @conversions['protip.messages.Date'] = {
      to_object: ->(message) { ::Date.new(message.year, message.month, message.day) },
      to_message: lambda do |date, message_class|
        raise ArgumentError unless date.is_a?(::Date)
        message_class.new year: date.year, month: date.month, day: date.day
      end
    }

    @conversions['protip.messages.Range'] = {
      to_object: ->(message) { message.begin..message.end },
      to_message: ->(range, message_class) do
        message_class.new(begin: range.begin.to_i, end: range.end.to_i)
      end
    }

    ## Standard wrappers
    %w(Int64 Int32 UInt64 UInt32 Double Float String Bytes).map{|type| "google.protobuf.#{type}Value"}.each do |name|
      @conversions[name] = {
        to_object: ->(message) { message.value },
        to_message: lambda do |value, message_class|
          message_class.new value: value
        end
      }
    end

    conversions['google.protobuf.BoolValue'] = {
      to_object: ->(message) { message.value },
      to_message: lambda do |value, message_class|
      message_class.new value: value_to_boolean(value)
    end
    }

    def convertible?(message_class)
      self.class.conversions.has_key?(message_class.descriptor.name)
    end

    def to_object(message)
      self.class.conversions[message.class.descriptor.name][:to_object].call(message)
    end

    def to_message(object, message_class)
      self.class.conversions[message_class.descriptor.name][:to_message].call(object, message_class)
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
    end
  end
end