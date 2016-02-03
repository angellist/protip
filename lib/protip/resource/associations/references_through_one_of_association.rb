require 'protip/resource/associations/reference'
require 'protip/resource/associations/references_through_association'

module Protip
  module Resource
    module Associations
      class ReferencesThroughOneOfAssociation

        include Protip::Resource::Associations::Reference
        attr_reader :resource_class, :reference_name

        def initialize(resource_class, oneof_name, reference_name: nil, field_options: {})
          @resource_class = resource_class
          @oneof_name = oneof_name.to_sym
          @reference_name = reference_name ||
            Protip::Resource::Associations::Reference.default_reference_name(@oneof_name)

          @_nested_references = {} # Store references for the sub-fields
          @oneof_field = @resource_class.message.descriptor.lookup_oneof(@oneof_name.to_s)
          @oneof_field.map do |field_descriptor|
            options = field_options[field_descriptor.name.to_s] || field_options[field_descriptor.name.to_sym] || {}
            @_nested_references[field_descriptor.name.to_sym] =
              Protip::Resource::Associations::ReferencesThroughAssociation.new(
                @resource_class, field_descriptor.name.to_sym, options
              )
          end
        end

        def read(resource)
          field = resource.message.public_send(@oneof_name)
          if field
            @_nested_references[field].read(resource)
          else
            nil
          end
        end

        def write(resource, value)
          if value == nil
            @oneof_field.each do |field_descriptor|
              resource.public_send(:"#{field_descriptor.name}=", nil)
            end
            nil
          else
            # Find the nested reference matching this association type
            matching_references = @_nested_references.select do |id_field, reference|
              value.is_a? reference.reference_class
            end

            # Make sure we found exactly one
            if matching_references.empty?
              raise ArgumentError.new("Could not find matching reference for value of type #{value.class}")
            end
            if matching_references.length > 1
              raise ArgumentError.new(
                      "Value of type #{value.class} matched with #{matching_references.keys.map(&:to_s).join(', ')}"
                    )
            end

            # And forward the write operation
            matching_references.values.first.write(resource, value)
          end
        end

        def define_accessors!
          @_nested_references.values.each{|reference| reference.define_accessors!}
          super
        end
      end
    end
  end
end