require 'active_support/concern'
require 'protobuf'

module Protip

  # Wraps a protobuf message to allow:
  # - getting/setting of certain message fields as if they were more complex Ruby objects
  # - mass assignment of attributes
  # - standardized creation of nested messages that can't be converted to/from Ruby objects
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

    # Create a nested field on our message. For example, given the following definitions:
    #
    #   message Inner {
    #     optional string str = 1;
    #   }
    #   message Outer {
    #     optional Inner inner = 1;
    #   }
    #
    # We could create an inner message using:
    #
    #   wrapper = Protip::Wrapper.new(Outer.new, converter)
    #   wrapper.inner # => nil
    #   wrapper.build(:inner, str: 'example')
    #   wrapper.inner.str # => 'example'
    #
    # Rebuilds the field if it's already present. Raises an error if the name of a primitive field
    # or a convertible message field is given.
    #
    # @param field_name [String|Symbol] The field name to build
    # @param attributes [Hash] The initial attributes to set on the field (as parsed by +assign_attributes+)
    # @return [Protip::Wrapper] The created field
    def build(field_name, attributes = {})

      field = message.class.fields.detect{|field| field.name == field_name.to_sym}
      if !field.is_a?(Protobuf::Field::MessageField)
        raise "Not a message field: #{field_name}"
      elsif converter.convertible?(field.type_class)
        raise "Cannot build a convertible field: #{field.name}"
      end

      message[field_name] = field.type_class.new
      wrapper = get(field)
      wrapper.assign_attributes attributes
      wrapper
    end

    # Mass assignment of message attributes. Nested messages will be built if necessary, but not overwritten
    # if they already exist.
    #
    # @param attributes [Hash] The attributes to set. Keys are field names. For primitive fields and message fields
    #   which are convertible to/from Ruby objects, values are the same as you'd pass to the field's setter
    #   method. For nested message fields which can't be converted to/from Ruby objects, values are attribute
    #   hashes which will be passed down to +assign_attributes+ on the nested field.
    # @return [NilClass]
    def assign_attributes(attributes)
      attributes.each do |field_name, value|
        field = message.class.fields.detect{|field| field.name == field_name.to_sym}

        # For inconvertible nested messages, the value should be a hash - just pass it through to the nested message
        if field.is_a?(Protobuf::Field::MessageField) && !converter.convertible?(field.type_class)
          wrapper = get(field) || build(field.name) # Create the field if it doesn't already exist
          wrapper.assign_attributes value
        # Otherwise, if the field is a convertible message or a simple type, we set the value directly
        else
          set(field, value)
        end
      end

      nil # Return nil to match ActiveRecord behavior
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