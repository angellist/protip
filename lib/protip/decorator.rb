require 'active_support/concern'

require 'protip/transformers/enum_transformer'

module Protip

  # Wraps a protobuf message to allow:
  # - getting/setting of message fields as if they were more complex Ruby objects
  # - mass assignment of attributes
  # - standardized creation of nested messages that can't be converted to/from Ruby objects
  class Decorator

    attr_reader :message, :transformer, :nested_resources

    def initialize(message, transformer, nested_resources={})
      @message = message
      @transformer = transformer
      @nested_resources = nested_resources
    end

    def inspect
      "<#{self.class.name}(#{transformer.class.name}) #{message.inspect}>"
    end

    def respond_to?(name, include_all=false)
      if super
        true
      else
        # Responds to calls to oneof groups by name
        return true if message.class.descriptor.lookup_oneof(name.to_s)

        # Responds to field getters, setters, and query methods for all fieldsfa
        field = message.class.descriptor.lookup(name.to_s.gsub(/[=?]$/, ''))
        return false if !field

        true
      end
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
    #   wrapper = Protip::Wrapper.new(Outer.new, transformer)
    #   wrapper.inner # => nil
    #   wrapper.build(:inner, str: 'example')
    #   wrapper.inner.str # => 'example'
    #
    # Assigns values by decorating an instance of the inner message,
    # passing in our transformer, and calling +assign_attributes+ on
    # the created decorator object.
    #
    # Rebuilds the field if it's already present. Raises an error if
    # the name of a primitive field is given.
    #
    # TODO: do we still need this or is it enough to just use
    # +decorator.field_name = hash+?
    #
    # @param field_name [String|Symbol] The field name to build
    # @param attributes [Hash] The initial attributes to set on the
    #   field (as parsed by +assign_attributes+) @return
    #   [Protip::Wrapper] The created field
    def build(field_name, attributes = {})

      field = message.class.descriptor.detect do |f|
        f.name.to_sym == field_name.to_sym
      end

      if !field
        raise "No field named #{field_name}"
      elsif field.type != :message
        raise "Can only build message fields: #{field_name}"
      end

      built = field.subtype.msgclass.new
      built_wrapper = self.class.new(built, transformer)
      built_wrapper.assign_attributes attributes
      message[field_name.to_s] = built_wrapper.message

      get(field)
    end

    # Mass assignment of message attributes. Nested messages will be
    # built if necessary, but not overwritten if they already exist.
    #
    # @param attributes [Hash] The attributes to set. Keys are field
    #   names. For primitive fields and message fields which are
    #   convertible to/from Ruby objects, values are the same as you'd
    #   pass to the field's setter method. For nested message fields
    #   which can't be converted to/from Ruby objects, values are
    #   attribute hashes which will be passed down to
    #   +assign_attributes+ on the nested field.  @return [NilClass]
    def assign_attributes(attributes)
      attributes.each do |field_name, value|
        field = message.class.descriptor.lookup(field_name.to_s) ||
          (raise ArgumentError.new("Unrecognized field: #{field_name}"))
        # Message fields can be set directly by Hash, which either
        # builds or updates them as appropriate.
        #
        # TODO: This kind of oddly assumes that the built message
        # responds to +assign_attributes+ (as it does when a
        # +DecoratingTransformer+ is used for the transformation). Can
        # be removed if we decide the update behavior is unnecessary,
        # since +DecoratingTransformer+ supports assignment by hash.
        if field.type == :message && value.is_a?(Hash)
          (get(field) || build(field.name)).assign_attributes value
        else
          set(field, value)
        end
      end

      nil # Return nil to match ActiveRecord behavior
    end

    def as_json
      to_h.as_json
    end

    # @return [Hash] A hash whose keys are the fields of our message,
    #   and whose values are the Ruby representations (either nested
    #   hashes or transformed messages) of the field values.
    def to_h
      hash = {}

      # Use nested +to_h+ on fields which are also decorated messages
      transform = ->(v) { v.is_a?(self.class) ? v.to_h : v }

      message.class.descriptor.each do |field|
        value = get(field)
        if field.label == :repeated
          value.map!{|v| transform[v]}
        else
          value = transform[value]
        end
        hash[field.name.to_sym] = value
      end
      hash
    end

    def ==(decorator)
      decorator.class == self.class &&
        decorator.message.class == message.class &&
        message.class.encode(message) == decorator.message.class.encode(decorator.message) &&
        transformer == decorator.transformer
    end

    class << self
      def enum_for_field(field)
        return nil if field.label == :repeated
        if field.type == :enum
          field.subtype
        elsif field.type == :message && field.subtype.name == 'protip.messages.EnumValue'
          Protip::Transformers::EnumTransformer.enum_for_field(field)
        else
          nil
        end
      end
    end

    private

    # Get the transformed value of the given field on our message.
    #
    # @param field [::Google::Protobuf::FieldDescriptor]
    def get(field)
      if field.label == :repeated
        message[field.name].map{|value| to_ruby_value field, value}
      else
        to_ruby_value field, message[field.name]
      end
    end

    # Helper for getting values - converts the value for the given
    # field to one that we can return to the user
    #
    # @param field [::Google::Protobuf::FieldDescriptor] The
    #   descriptor for the field we're fetching.
    # @param value [Object] The message or primitive value of the
    #   field.
    def to_ruby_value(field, value)
      if field.type == :message
        field_name_sym = field.name.to_sym
        if nil == value
          nil
        elsif nested_resources.has_key?(field_name_sym)
          resource_klass = nested_resources[field_name_sym]
          resource_klass.new value
        else
          transformer.to_object value, field
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

    # Helper for setting values - converts the value for the given
    # field to one that we can set directly
    def to_protobuf_value(field, value)
      if field.type == :message
        if nil == value
          nil
        # This check must happen before the nested_resources check to
        # ensure nested messages are set properly
        elsif value.is_a?(field.subtype.msgclass)
          value
        elsif nested_resources.has_key?(field.name.to_sym)
          value.message
        else
          transformer.to_message(value, field)
        end
      elsif field.type == :enum
        value.is_a?(Fixnum) ? value : value.to_sym
      else
        value
      end
    end

    def matches?(field, value)
      enum = Protip::Decorator.enum_for_field(field)
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
      raise NoMethodError unless field

      if nil != Protip::Decorator.enum_for_field(field) && args.length == 1
        matches?(field, args[0])
      elsif args.length == 0
        value = get(field)

        # Copied in from ActiveSupport +.blank?+
        blank = (value.respond_to?(:empty?) ? !!value.empty? : !value)
        !blank
      else
        raise ArgumentError
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
