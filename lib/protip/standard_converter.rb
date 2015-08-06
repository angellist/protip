require 'protip/converter'

require 'protip/messages/types'
require 'google/protobuf'

module Protip
  class StandardConverter
    include Protip::Converter

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

    ## Standard wrappers
    %w(Int64 Int32 UInt64 UInt32 Double Float Bool String Bytes).map{|type| "google.protobuf.#{type}Value"}.each do |name|
      @conversions[name] = {
        to_object: ->(message) { message.value },
        to_message: lambda do |value, message_class|
          message_class.new value: value
        end
      }
    end

    def convertible?(message_class)
      self.class.conversions.has_key?(message_class.descriptor.name)
    end

    def to_object(message)
      self.class.conversions[message.class.descriptor.name][:to_object].call(message)
    end

    def to_message(object, message_class)
      self.class.conversions[message_class.descriptor.name][:to_message].call(object, message_class)
    end
  end
end