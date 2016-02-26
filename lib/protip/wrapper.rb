require 'active_support/concern'

module Protip

  # Wraps a protobuf message to allow:
  # - getting/setting of certain message fields as if they were more complex Ruby objects
  # - mass assignment of attributes
  # - standardized creation of nested messages that can't be converted to/from Ruby objects
  class Wrapper

    attr_reader :message, :converter, :nested_resources

    def initialize(message, converter, nested_resources={})
      @message = message
      @converter = converter
      @nested_resources = nested_resources
    end

    def respond_to?(name)
      if super
        return true
      else
        # Responds to calls to oneof groups by name
        return true if message.class.descriptor.lookup_oneof(name.to_s)

        # Responds to field getters, setters, and in the scalar enum case, query methods
        field = message.class.descriptor.lookup(name.to_s.gsub(/[=?]$/, ''))
        return false if !field
        if name[-1, 1] == '?'
          # For query methods, only respond  if the field is matchable
          return self.class.matchable?(field)
        else
          return true
        end
      end
      false
    end

    def method_missing(name, *args)
      descriptor = message.class.descriptor
      name = name.to_s
      last_char = name[-1, 1]

      if last_char == '='
        return method_missing_set(name, *args)
      end

      if last_char == '?'
        return method_missing_query(name, *args)
      end

      field = descriptor.lookup(name)
      if field
        return method_missing_field(field, *args)
      end

      oneof = descriptor.lookup_oneof(name)
      # For calls to a oneof group, return the active oneof field, or nil if there isn't one
      if oneof
        return method_missing_oneof(oneof, *args)
      end

      super
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

      field = message.class.descriptor.detect{|field| field.name.to_sym == field_name.to_sym}
      if !field
        raise "No field named #{field_name}"
      elsif field.type != :message
        raise "Can only build message fields: #{field_name}"
      elsif converter.convertible?(field.subtype.msgclass)
        raise "Cannot build a convertible field: #{field.name}"
      end

      message[field_name.to_s] = field.subtype.msgclass.new
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
        field = message.class.descriptor.lookup(field_name.to_s) ||
          (raise ArgumentError.new("Unrecognized field: #{field_name}"))

        # For inconvertible nested messages, we allow a hash to be passed in with nested attributes
        if field.type == :message && !converter.convertible?(field.subtype.msgclass) && value.is_a?(Hash)
          wrapper = get(field) || build(field.name) # Create the field if it doesn't already exist
          wrapper.assign_attributes value
        # Otherwise, if the field is a message (convertible or not) or a simple type, we set the value directly
        else
          set(field, value)
        end
      end

      nil # Return nil to match ActiveRecord behavior
    end

    def as_json
      to_h.as_json
    end

    # @return [Hash] A hash whose keys are the fields of our message, and whose values are the Ruby representations
    #   (either nested hashes or converted messages) of the field values.
    def to_h
      hash = {}
      message.class.descriptor.each do |field|
        value = public_send(field.name)
        if field.label == :repeated
          value.map!{|v| v.is_a?(self.class) ? v.to_h : v}
        else
          value = (value.is_a?(self.class) ? value.to_h : value)
        end
        hash[field.name.to_sym] = value
      end
      hash
    end

    def ==(wrapper)
      wrapper.class == self.class &&
        wrapper.message.class == message.class &&
        message.class.encode(message) == wrapper.message.class.encode(wrapper.message) &&
        converter == wrapper.converter
    end

    class << self
      # Semi-private check for whether a field should have an associated query method (e.g. +field_name?+).
      # @return [Boolean] Whether the field should have an associated query method on wrappers.
      def matchable?(field)
        return false if field.label == :repeated

        field.type == :enum ||
            field.type == :bool ||
            field.type == :message && (field.subtype.name == "google.protobuf.BoolValue")
      end
    end

    private

    def get(field)
      if field.label == :repeated
        message[field.name].map{|value| to_ruby_value field, value}
      else
        to_ruby_value field, message[field.name]
      end
    end

    # Helper for getting values - converts the value for the given field to one that we can return to the user
    def to_ruby_value(field, value)
      if field.type == :message
        field_name_sym = field.name.to_sym
        if nil == value
          nil
        elsif converter.convertible?(field.subtype.msgclass)
          converter.to_object value
        elsif nested_resources.has_key?(field_name_sym)
          resource_klass = nested_resources[field_name_sym]
          resource_klass.new value
        else
          self.class.new value, converter
        end
      else
        value
      end
    end

    def set(field, value)
      if field.label == :repeated
        message[field.name].replace value.map{|v| to_protobuf_value field, v}
      else
        message[field.name] = to_protobuf_value(field, value)
      end
    end

    # Helper for setting values - converts the value for the given field to one that we can set directly
    def to_protobuf_value(field, value)
      if field.type == :message
        if nil == value
          nil
        # This check must happen before the nested_resources check to ensure nested messages
        # are set properly
        elsif value.is_a?(field.subtype.msgclass)
          value
        elsif converter.convertible?(field.subtype.msgclass)
          converter.to_message value, field.subtype.msgclass
        elsif nested_resources.has_key?(field.name.to_sym)
          value.message
        else
          raise ArgumentError.new "Cannot convert from Ruby object: \"#{field.name}\""
        end
      elsif field.type == :enum
        value.is_a?(Fixnum) ? value : value.to_sym
      else
        value
      end
    end

    def matches?(field, value)
      enum = field.subtype
      if value.is_a?(Fixnum)
        sym = enum.lookup_value(value)
      else
        sym = value.to_sym
        sym = nil if (nil == enum.lookup_name(sym))
      end
      raise RangeError.new("#{field} has no value #{value}") if nil == sym
      get(field) == sym

    end

    def method_missing_oneof(oneof, *args)
      raise ArgumentError unless args.length == 0
      field_name = message.public_send(oneof.name)

      field_name ? get(message.class.descriptor.lookup(field_name.to_s)) : nil
    end

    def method_missing_field(field, *args)
      raise ArgumentError unless args.length == 0
      get field
    end

    def method_missing_query(name, *args)
      field = message.class.descriptor.lookup(name[0, name.length - 1])
      raise NoMethodError if !field || !self.class.matchable?(field)
      if field.type == :enum
        raise ArgumentError unless args.length == 1
        return matches?(field, args[0])
      elsif field.type == :bool ||
        (field.type == :message && field.subtype.name == 'google.protobuf.BoolValue')
      else
        raise NoMethodError
      end
    end

    def method_missing_set(name, *args)
      raise ArgumentError unless args.length == 1
      field = message.class.descriptor.lookup(name[0, name.length - 1])
      raise(NoMethodError.new) unless field
      set(field, args[0])
    end
  end
end