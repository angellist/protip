require 'active_support/concern'
require 'protobuf'

module Protip
  class Wrapper
    attr_reader :message, :converter
    def initialize(message, converter)
      @message = message
      @converter = converter
    end

    def respond_to?(name)
      if super
        true
      else
        if name =~ /=$/
          message.class.fields.any?{|field| :"#{field.name}=" == name.to_sym}
        else
          message.class.fields.any?{|field| field.name == name.to_sym}
        end
      end
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

    def as_json
      json = {}
      message.class.fields.each do |name|
        value = public_send(name)
        json[name.to_s] = value.respond_to?(:as_json) ? value.as_json : value
      end
      json
    end

    def ==(wrapper)
      message == wrapper.message && converter == wrapper.converter
    end

    private

    def get(field)
      if field.is_a?(Protobuf::Field::MessageField)
        if message[field.name].nil?
          nil
        else
          if converter.convertible?(field.type_class)
            converter.to_object message[field.name]
          else
            self.class.new message[field.name], converter
          end
        end
      else
        message[field.name]
      end
    end

    def set(field, value)
      if field.is_a?(Protobuf::Field::MessageField)
        if value.is_a? Protobuf::Message
          message[field.name] = value
        elsif converter.convertible?(field.type_class)
          message[field.name] = converter.to_message value, field.type_class
        else
          raise ArgumentError.new "Cannot convert from Ruby object: \"#{field}\""
        end
      else
        message[field.name] = value
      end
    end
  end
end