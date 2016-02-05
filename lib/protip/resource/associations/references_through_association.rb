require 'active_support/core_ext/string/inflections' # For classifying/constantizing strings

require 'protip/resource/associations/reference'

module Protip
  module Resource
    module Associations
      class ReferencesThroughAssociation

        include Protip::Resource::Associations::Reference

        attr_reader :resource_class, :reference_name

        def initialize(resource_class, id_field, reference_name: nil, class_name: nil)
          # The resource type that houses the association
          @resource_class = resource_class

          # The field that holds the ID for the association
          @id_field = id_field.to_sym

          # The name for generating accessor methods
          @reference_name = (
            reference_name || Protip::Resource::Associations::Reference.default_reference_name(id_field)
          ).to_sym

          @class_name = (class_name || self.class.default_class_name(@id_field)).to_s
        end

        def reference_class
          @reference_class ||= @class_name.constantize
        end

        def read(resource)
          id = resource.public_send(@id_field)
          if id == nil
            nil
          else
            reference_class.find id
          end
        end

        def write(resource, value)
          if value != nil
            unless value.is_a?(reference_class)
              raise ArgumentError.new("Cannot assign #{value.class} to #{resource_class}##{@id_field}")
            end
            unless value.persisted?
              raise "Cannot assign non-persisted resource to association #{resource_class}##{reference_name}"
            end
          end
          resource.public_send(:"#{@id_field}=", value.try(:id))
        end

        class << self
          def default_class_name(id_field)
            Protip::Resource::Associations::Reference.default_reference_name(id_field).to_s.classify
          end
        end
      end
    end
  end
end