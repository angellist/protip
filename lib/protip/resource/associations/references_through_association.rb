require 'protip/resource/associations/reference'

module Protip
  module Resource
    module Associations
      class ReferencesThroughAssociation

        include Protip::Resource::Associations::Reference

        attr_reader :resource_class, :reference_name

        def initialize(resource_class, id_field, reference_name: nil, class_name: nil)
          @resource_class = resource_class
          @id_field = id_field.to_sym
          @reference_name = (
            reference_name || Protip::Resource::Associations::Reference.default_reference_name(id_field)
          ).to_sym
          @class_name = nil
        end

        def read(resource)
          id = resource.public_send(@id_field)
          if id == nil
            nil
          else
            @class_name.find id
          end
        end

        def write(resource, value)
          # TODO: error if a value with an empty ID is passed in?
          resource.public_send(:"#{@id_field}=", value.try(:id))
        end
      end
    end
  end
end