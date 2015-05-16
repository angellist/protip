require 'active_support/concern'
require 'protobuf'

module Protip
  module MessageWrapper
    extend ActiveSupport::Concern

    attr_reader :message
    def initialize(message)
      @message = message
    end

    def method_missing(name, *args)
      if (name =~ /=$/ && field = message.class.fields.detect{|field| :"#{field.name}=" == name})
        raise ArgumentError unless args.length == 1
        set field, args[0]
      elsif (field = message.class.fields.detect{|field| field.name == name})
        raise ArgumentError unless args.length == 0
        get field
      else
        super
      end
    end

    module ClassMethods
      def convertible?(type_class)
        raise NotImplementedError.new(
          'Must specify whether a message of a given type can be converted to/from a Ruby object'
        )
      end

      def to_object(message)
        raise NotImplementedError.new('Must convert a message into a Ruby object')
      end

      def to_message(object, type_class)
        raise NotImplementedError.new('Must convert a Ruby object into a message of the given type')
      end
    end

    private

    def get(field)
      if field.is_a?(Protobuf::Field::MessageField)
        if self.class.convertible?(field.type_class)
          self.class.to_object message[field.name]
        else
          self.class.new message[field.name]
        end
      else
        message[field.name]
      end
    end

    def set(field, value)
      if field.is_a?(Protobuf::Field::MessageField)
        if value.is_a? Protobuf::Message
          message[field.name]
        elsif self.class.convertible?(field.type_class)
          message[field.name] = self.class.to_message value, field.type_class
        else
          raise ArgumentError.new "Cannot convert from Ruby object: \"#{field}\""
        end
      else
        message[field.name] = value
      end
    end
  end

end