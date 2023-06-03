require 'active_support/core_ext/string/inflections' # For classifying/constantizing strings

require 'protip/resource/associations/association'

module Protip
  module Resource
    module Associations
      class BelongsToAssociation

        include Protip::Resource::Associations::Association

        attr_reader :resource_class, :association_name, :id_field

        def initialize(resource_class, association_name, id_field: nil, class_name: nil)
          # The resource type that houses the association
          @resource_class = resource_class

          # The name for generating accessor methods
          @association_name = association_name

          # The field that holds the ID for the association
          @id_field = (id_field || self.class.default_id_field(association_name)).to_sym

          @class_name = (class_name || self.class.default_class_name(association_name)).to_s
        end

        def associated_resource_class
          @associated_resource_class ||= @class_name.constantize
        end

        def read(resource)
          id = resource.public_send(@id_field)
          if id == nil
            nil
          else
            associated_resource_class.find id
          end
        end

        def write(resource, value)
          if value != nil
            unless value.is_a?(associated_resource_class)
              raise ArgumentError.new("Cannot assign #{value.class} to #{resource_class}##{@id_field}")
            end
            unless value.persisted?
              raise "Cannot assign non-persisted resource to association #{resource_class}##{association_name}"
            end
          end
          resource.public_send(:"#{@id_field}=", value.try(:id))
        end

        class << self
          def default_id_field(association_name)
            "#{association_name}_id".to_sym
          end
          def default_class_name(association_name)
            association_name.to_s.classify
          end
        end

      end
    end
  end
end
