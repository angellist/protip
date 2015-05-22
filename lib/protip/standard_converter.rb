require 'protip/converter'

require 'protobuf'
require 'protip/messages/types.pb'
require 'protip/messages/wrappers.pb'

module Protip
  class StandardConverter
    include Protip::Converter

    class << self
      attr_reader :conversions
    end
    @conversions = {}

    ## Protip types
    @conversions[Protip::Date] = {
      to_object: ->(message) { ::Date.new(message.year, message.month, message.day) },
      to_message: lambda do |date|
        raise ArgumentError unless date.is_a?(::Date)
        Protip::Date.new year: date.year, month: date.month, day: date.day
      end
    }

    ## Standard wrappers
    [Protip::Int64Value, Protip::Int32Value, Protip::UInt64Value, Protip::UInt32Value].each do |message_class|
      @conversions[message_class] = {
        to_object: ->(message) { message.value },
        to_message: lambda do |integer|
          raise ArgumentError unless integer.is_a?(Integer)
          message_class.new value: integer
        end
      }
    end
    [Protip::DoubleValue, Protip::FloatValue].each do |message_class|
      @conversions[message_class] = {
        to_object: ->(message) { message.value },
        to_message: lambda do |float|
          raise ArgumentError unless float.is_a?(Float)
          message_class.new value: float
        end
      }
    end
    [Protip::BoolValue].each do |message_class|
      @conversions[message_class] = {
        to_object: ->(message) { message.value },
        to_message: lambda do |bool|
          # Protobuf throws a type error if this isn't the correct type, so we don't need to check
          message_class.new value: bool
        end
      }
    end
    [Protip::StringValue, Protip::BytesValue].each do |message_class|
      @conversions[message_class] = {
        to_object: ->(message) { message.value },
        to_message: lambda do |string|
          # Protobuf throws a type error if this isn't the correct type, so we don't need to check
          message_class.new value: string
        end
      }
    end

    def convertible?(message_class)
      self.class.conversions.has_key?(message_class)
    end

    def to_object(message)
      self.class.conversions[message.class][:to_object].call(message)
    end

    def to_message(object, message_class)
      self.class.conversions[message_class][:to_message].call(object)
    end
  end
end