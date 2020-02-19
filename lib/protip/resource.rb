# Missing dependencies from the other requires
require 'active_model/callbacks'
require 'active_model/validator'
require 'active_support/callbacks'
require 'active_support/core_ext/module/delegation'
require 'active_support/core_ext/object/try'

require 'active_support/concern'
require 'active_support/core_ext/object/blank'

require 'active_model/validations'
require 'active_model/conversion'
require 'active_model/naming'
require 'active_model/translation'
require 'active_model/errors'

require 'active_model/attribute_methods' # ActiveModel::Dirty depends on this
require 'active_model/dirty'

require 'forwardable'

require 'protip/client'
require 'protip/error'
require 'protip/decorator'
require 'protip/transformers/default_transformer'

require 'protip/messages/array_pb'

require 'protip/resource/creatable'
require 'protip/resource/updateable'
require 'protip/resource/destroyable'
require 'protip/resource/extra_methods'
require 'protip/resource/search_methods'
require 'protip/resource/associations/belongs_to_association'
require 'protip/resource/associations/belongs_to_polymorphic_association'

module Protip
  module Resource
    extend ActiveSupport::Concern

    # Backport the ActiveModel::Model functionality
    # https://github.com/rails/rails/blob/097ca3f1f84bb9a2d3cda3f2cce7974a874efdf4/activemodel/lib/active_model/model.rb#L95
    include ActiveModel::Validations
    include ActiveModel::Conversion

    include ActiveModel::Dirty

    included do
      extend ActiveModel::Naming
      extend ActiveModel::Translation
      extend Forwardable

      def_delegator :@decorator, :message
      def_delegator :@decorator, :as_json

      # Initialize housekeeping variables
      @belongs_to_associations = Set.new
      @belongs_to_polymorphic_associations = Set.new
    end

    module ClassMethods

      VALID_ACTIONS = %i(show index create update destroy)

      attr_accessor :client

      attr_reader :message, :nested_resources, :belongs_to_associations, :belongs_to_polymorphic_associations

      attr_writer :base_path, :transformer

      def base_path
        if @base_path == nil
          raise(RuntimeError.new 'Base path not yet set')
        else
          @base_path.gsub(/\/$/, '')
        end
      end

      def transformer
        defined?(@transformer) ? @transformer : ::Protip.default_transformer
      end

      private

      # Primary entry point for defining resourceful behavior.
      def resource(actions:, message:, query: nil, nested_resources: {})
        raise RuntimeError.new('Only one call to `resource` is allowed') if defined?(@message) && @message
        validate_actions!(actions)
        validate_nested_resources!(nested_resources)

        @message = message
        @nested_resources = nested_resources

        define_attribute_accessors(@message)
        define_oneof_group_methods(@message)
        define_resource_query_methods(query, actions)

        include(::Protip::Resource::Creatable) if actions.include?(:create)
        include(::Protip::Resource::Updatable) if actions.include?(:update)
        include(::Protip::Resource::Destroyable) if actions.include?(:destroy)
      end

      def validate_nested_resources!(nested_resources)
        nested_resources.each do |key, resource_klass|
          unless key.is_a?(Symbol)
            raise "#{key} must be a Symbol, but is a #{key.class}"
          end
          unless resource_klass < ::Protip::Resource
            raise "#{resource_klass} is not a Protip::Resource"
          end
        end
      end

      def validate_actions!(actions)
        actions.map!{|action| action.to_sym}
        (actions - VALID_ACTIONS).each do |action|
          raise ArgumentError.new("Unrecognized action: #{action}")
        end
      end

      # Allow calls to oneof groups to get the set oneof field
      def define_oneof_group_methods(message)
        message.descriptor.each_oneof do |oneof_field|
          def_delegator :@decorator, :"#{oneof_field.name}"
        end
      end

      # Define attribute readers/writers
      def define_attribute_accessors(message)
        message.descriptor.each do |field|
          def_delegator :@decorator, :"#{field.name}"
          def_delegator :@decorator, :"#{field.name}?"

          define_method "#{field.name}=" do |new_value|
            old_value = self.message[field.name] # Only compare the raw values
            @decorator.send("#{field.name}=", new_value)
            new_value = self.message[field.name]

            # Need to check that types are the same first, otherwise protobuf gets mad comparing
            # messages with non-messages
            send("#{field.name}_will_change!") unless new_value.class == old_value.class && new_value == old_value
          end

          # needed for ActiveModel::Dirty
          define_attribute_method field.name
        end
      end

      # For index/show, we want a different number of method arguments
      # depending on whether a query message was provided.
      def define_resource_query_methods(query, actions)
        if query
          if actions.include?(:show)
            define_singleton_method :find do |id, query_params = {}|
              message = nil
              if query_params.is_a?(query)
                message = query_params
              else
                decorator = ::Protip::Decorator.new(query.new, transformer)
                decorator.assign_attributes query_params
                message = decorator.message
              end
              ::Protip::Resource::SearchMethods.show(self, id, message)
            end
          end

          if actions.include?(:index)
            define_singleton_method :all do |query_params = {}|
              message = nil
              if query_params.is_a?(query)
                message = query_params
              else
                decorator = ::Protip::Decorator.new(query.new, transformer)
                decorator.assign_attributes query_params
                message = decorator.message
              end
              ::Protip::Resource::SearchMethods.index(self, message)
            end
          end
        else
          if actions.include?(:show)
            define_singleton_method :find do |id|
              ::Protip::Resource::SearchMethods.show(self, id, nil)
            end
          end

          if actions.include?(:index)
            define_singleton_method :all do
              ::Protip::Resource::SearchMethods.index(self, nil)
            end
          end
        end
      end

      def member(action:, method:, request: nil, response: nil)
        if request
          define_method action do |request_params = {}|
            message = nil
            if request_params.is_a?(request) # Message provided directly
              message = request_params
            else # Parameters provided by hash
              decorator = ::Protip::Decorator.new(request.new, self.class.transformer)
              decorator.assign_attributes request_params
              message = decorator.message
            end
            ::Protip::Resource::ExtraMethods.member self,
              action, method, message, response
          end
        else
          define_method action do
            ::Protip::Resource::ExtraMethods.member self, action, method, nil, response
          end
        end
      end

      def collection(action:, method:, request: nil, response: nil)
        if request
          define_singleton_method action do |request_params = {}|
            message = nil
            if request_params.is_a?(request) # Message provided directly
              message = request_params
            else # Parameters provided by hash
              decorator = ::Protip::Decorator.new(request.new, transformer)
              decorator.assign_attributes request_params
              message = decorator.message
            end
            ::Protip::Resource::ExtraMethods.collection self,
              action, method, message, response
          end
        else
          define_singleton_method action do
            ::Protip::Resource::ExtraMethods.collection self, action, method, nil, response
          end
        end
      end

      def belongs_to(association_name, options = {})
        association = ::Protip::Resource::Associations::BelongsToAssociation.new(self, association_name, options)
        association.define_accessors!
        @belongs_to_associations.add association
        association
      end

      def belongs_to_polymorphic(association_name, options = {}, &block)
        # We evaluate the block in the context of a wrapper that
        # stores simple belongs-to associations as they're being
        # created.
        nested_association_creator = Class.new do
          attr_reader :associations
          def initialize(resource_class)
            @resource_class = resource_class
            @associations = []
          end
          def belongs_to(*args)
            # Just forward the belongs_to call and store the result so we can pass it to the polymorphic association
            @associations << @resource_class.send(:belongs_to, *args)
          end
        end.new(self)

        nested_association_creator.instance_eval(&block)

        association = ::Protip::Resource::Associations::BelongsToPolymorphicAssociation.new self,
          association_name, nested_association_creator.associations, options
        association.define_accessors!
        @belongs_to_polymorphic_associations.add association
        association
      end

      def references_through_one_of(id_field, options = {})
        ::Protip::Resource::Associations::ReferencesThroughOneOfAssociation.new(self, id_field, options)
          .define_accessors!
      end
    end

    def initialize(message_or_attributes = {})
      if self.class.message == nil
        raise RuntimeError.new('Must define a message class using `resource`')
      end
      if message_or_attributes.is_a?(self.class.message)
        self.message = message_or_attributes
      else
        self.message = self.class.message.new
        assign_attributes message_or_attributes
      end

      super()
    end

    def assign_attributes(attributes)
      old_attributes = {}
      descriptor = message.class.descriptor
      keys = attributes.keys.map(&:to_s)
      keys.each do |key|
        field = descriptor.lookup(key)
        value = message[key]
        # If the current value is a message, we need to clone it to get a reasonable comparison later,
        # since we might just assign attributes to the current instance of the message directly
        old_attributes[key] = field && field.type == :message && value ? value.clone : value
      end
      @decorator.assign_attributes attributes
      keys.each do |key|
        old_value = old_attributes[key]
        new_value = message[key]
        changed = !(old_value.class == new_value.class && old_value == new_value)

        if changed
          send "#{key}_will_change!"
        end
      end
      nil # return nil to match ActiveRecord behavior
    end

    def message=(message)
      @decorator = Protip::Decorator.new(message,
        self.class.transformer, self.class.nested_resources)
    end

    def save
      success = true
      begin
        if persisted?
          # TODO: use `ActiveModel::Dirty` to only send changed attributes?
          update!
        else
          create!
        end
        changes_applied
      rescue Protip::UnprocessableEntityError => error
        success = false
        error.errors.messages.each do |message|
          errors.add :base, message
        end
        error.errors.field_errors.each do |field_error|
          errors.add field_error.field, field_error.message
        end
      end
      success
    end

    class RecordInvalid < StandardError
    end

    def save!
      success = save
      if !success
        error_messages = errors.full_messages.join(", ")
        raise RecordInvalid.new("Validation failed: #{error_messages}")
      end
      success
    end

    def persisted?
      id != nil
    end

    def attributes
      # Like `.as_json`, but includes nil fields to match ActiveRecord behavior.
      self.class.message.descriptor.map{|field| field.name}.inject({}) do |hash, attribute_name|
        hash[attribute_name] = public_send(attribute_name)
        hash
      end
    end

    def errors
      @errors ||= ActiveModel::Errors.new(self)
    end
  end
end
