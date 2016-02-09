# Base module for a reference that can be defined on a resource. References
# are similar to +belongs_to+ associations in ActiveRecord.
module Protip
  module Resource
    module Associations
      module Association

        def define_accessors!
          resource_class.class_exec(self, association_name) do |association, association_name|
            define_method(association_name) do
              association.read(self)
            end

            define_method(:"#{association_name}=") do |value|
              association.write(self, value)
            end
          end
        end

        # Individual reference classes must implement
        def resource_class
          raise NotImplementedError
        end

        def association_name
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