# Base module for a reference that can be defined on a resource. References
# are similar to +belongs_to+ associations in ActiveRecord.
module Protip
  module Resource
    module Associations
      module Reference

        def define_accessors!
          resource_class.class_exec(self, reference_name) do |association, reference_name|
            define_method(reference_name) do
              association.read(self)
            end

            define_method(:"#{reference_name}=") do |value|
              association.write(self, value)
            end
          end
        end

        class << self
          def default_reference_name(field)
            default = field.to_s.gsub(/_id$/, '').to_sym
            if default.to_s == field.to_s
              raise "Cannot create a default reference name for field #{field}"
            end
            default
          end
        end

        # Individual reference classes must implement
        def resource_class
          raise NotImplementedError
        end

        def reference_name
          raise NotImplementedError
        end

        def read(resource)
          raise NotImplementedError
        end

        def write(resource, value)
          raise NotImplementedError
        end
      end
    end
  end
end