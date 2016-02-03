require 'protip/resource/associations/reference'
require 'protip/resource/associations/references_through_association'

module Protip
  module Resource
    module Associations
      class ReferencesThroughOneOfAssociation
        def initialize(resource_class, oneof_field, reference_name: nil, field_options: {})
          @resource_class = resource_class
          @oneof_field = oneof_field
          @reference_name = reference_name ||
            Protip::Resource::Associations::Reference.default_reference_name(oneof_field)
        end

        def read(resource)

        end

        def write(resource, association)

        end
      end
    end
  end
end