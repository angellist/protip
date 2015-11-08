# Missing dependencies from the other requires
require 'active_model/callbacks'
require 'active_model/validator'
require 'active_support/callbacks'
require 'active_support/core_ext/module/delegation'

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

require 'protip/error'
require 'protip/standard_converter'
require 'protip/wrapper'

require 'protip/messages/array'

module Protip
  module Resource

    # Internal handlers for index/show actions. Never use these directly; instead, use `.all` and
    # `.find` on the resource you're working with, since those methods will adjust their
    # signatures to correctly parse a set of query parameters if supported.
    module SearchMethods
      # Fetch a list from the server at the collection's base endpoint. Expects the server response
      # to be an array containing encoded messages that can be used to instantiate our resource.
      #
      # @param resource_class [Class] The resource type that we're fetching.
      # @param query [::Protobuf::Message|NilClass] An optional query to send along with the request.
      # @return [Array] The array of resources (each is an instance of the resource class we were
      #   initialized with).
      def self.index(resource_class, query)
        response = resource_class.client.request path: resource_class.base_path,
          method: Net::HTTP::Get,
          message: query,
          response_type: Protip::Messages::Array
        response.messages.map do |message|
          resource_class.new resource_class.message.decode(message)
        end
      end

      # Fetch a single resource from the server.
      #
      # @param resource_class [Class] The resource type that we're fetching.
      # @param id [String] The ID to be used in the URL to fetch the resource.
      # @param query [::Protobuf::Message|NilClass] An optional query to send along with the request.
      # @return [Protip::Resource] An instance of our resource class, created from the server
      #   response.
      def self.show(resource_class, id, query)
        response = resource_class.client.request path: "#{resource_class.base_path}/#{id}",
          method: Net::HTTP::Get,
          message: query,
          response_type: resource_class.message
        resource_class.new response
      end
    end

    # Mixin for a resource that has an active `:create` action. Should be treated as private,
    # and will be included automatically when appropriate.
    module Creatable
      private
      # POST the resource to the server and update our internal message. Private, since
      # we should generally do this through the `save` method.
      def create!
        raise RuntimeError.new("Can't re-create a persisted object") if persisted?
        self.message = self.class.client.request path: self.class.base_path,
          method: Net::HTTP::Post,
          message: message,
          response_type: self.class.message
      end
    end

    # Mixin for a resource that has an active `:update` action. Should be treated as private,
    # and will be included automatically when appropriate.
    module Updatable
      private
      # PUT the resource on the server and update our internal message. Private, since
      # we should generally do this through the `save` method.
      def update!
        raise RuntimeError.new("Can't update a non-persisted object") if !persisted?
        self.message = self.class.client.request path: "#{self.class.base_path}/#{id}",
          method: Net::HTTP::Put,
          message: message,
          response_type: self.class.message
      end
    end

    # Mixin for a resource that has an active `:destroy` action. Should be treated as private,
    # and will be included automatically when appropriate.
    module Destroyable
      def destroy
        raise RuntimeError.new("Can't destroy a non-persisted object") if !persisted?
        self.message = self.class.client.request path: "#{self.class.base_path}/#{id}",
          method: Net::HTTP::Delete,
          message: nil,
          response_type: self.class.message
      end
    end

    # Internal helpers for non-resourceful member/collection methods. Never use these directly;
    # instead, use the instance/class methods which have been dynamically defined on the resource
    # you're working with.
    module ExtraMethods
      def self.member(resource, action, method, message, response_type)
        response = resource.class.client.request path: "#{resource.class.base_path}/#{resource.id}/#{action}",
          method: method,
          message: message,
          response_type: response_type
        nil == response ? nil : ::Protip::Wrapper.new(response, resource.class.converter)
      end
      def self.collection(resource_class, action, method, message, response_type)
        response = resource_class.client.request path: "#{resource_class.base_path}/#{action}",
          method: method,
          message: message,
          response_type: response_type
        nil == response ? nil : ::Protip::Wrapper.new(response, resource_class.converter)
      end
    end

    extend ActiveSupport::Concern

    # Backport the ActiveModel::Model functionality - https://github.com/rails/rails/blob/097ca3f1f84bb9a2d3cda3f2cce7974a874efdf4/activemodel/lib/active_model/model.rb#L95
    include ActiveModel::Validations
    include ActiveModel::Conversion

    include ActiveModel::Dirty

    included do
      extend ActiveModel::Naming
      extend ActiveModel::Translation
      extend Forwardable

      def_delegator :@wrapper, :message
      def_delegator :@wrapper, :as_json
    end
    module ClassMethods

      attr_accessor :client

      attr_reader :message

      attr_writer :base_path
      def base_path
        @base_path == nil ? raise(RuntimeError.new 'Base path not yet set') : @base_path.gsub(/\/$/, '')
      end

      attr_writer :converter
      def converter
        @converter || (@_standard_converter ||= Protip::StandardConverter.new)
      end

      private

      # Primary entry point for defining resourceful behavior.
      def resource(actions:, message:, query: nil)
        if @message
          raise RuntimeError.new('Only one call to `resource` is allowed')
        end

        # Define attribute readers/writers
        @message = message
        @message.descriptor.each do |field|
          def_delegator :@wrapper, :"#{field.name}"
          if ::Protip::Wrapper.matchable?(field)
            def_delegator :@wrapper, :"#{field.name}?"
          end

          define_method "#{field.name}=" do |new_value|
            old_wrapped_value = @wrapper.send(field.name)
            @wrapper.send("#{field.name}=", new_value)
            new_wrapped_value = @wrapper.send(field.name)

            # needed for ActiveModel::Dirty
            send("#{field.name}_will_change!") if new_wrapped_value != old_wrapped_value
          end
        end

        # Allow calls to oneof groups to get the set oneof field
        @message.descriptor.each_oneof do |oneof_field|
          def_delegator :@wrapper, :"#{oneof_field.name}"
        end

        # needed for ActiveModel::Dirty
        define_attribute_methods @message.descriptor.map(&:name)

        # Validate arguments
        actions.map!{|action| action.to_sym}
        (actions - %i(show index create update destroy)).each do |action|
          raise ArgumentError.new("Unrecognized action: #{action}")
        end

        # For index/show, we want a different number of method arguments
        # depending on whehter a query message was provided.
        if query
          if actions.include?(:show)
            define_singleton_method :find do |id, query_params = {}|
              wrapper = ::Protip::Wrapper.new(query.new, converter)
              wrapper.assign_attributes query_params
              SearchMethods.show(self, id, wrapper.message)
            end
          end

          if actions.include?(:index)
            define_singleton_method :all do |query_params = {}|
              wrapper = ::Protip::Wrapper.new(query.new, converter)
              wrapper.assign_attributes query_params
              SearchMethods.index(self, wrapper.message)
            end
          end
        else
          if actions.include?(:show)
            define_singleton_method :find do |id|
              SearchMethods.show(self, id, nil)
            end
          end

          if actions.include?(:index)
            define_singleton_method :all do
              SearchMethods.index(self, nil)
            end
          end
        end

        include(Creatable) if actions.include?(:create)
        include(Updatable) if actions.include?(:update)
        include(Destroyable) if actions.include?(:destroy)
      end

      def member(action:, method:, request: nil, response: nil)
        if request
          define_method action do |request_params = {}|
            wrapper = ::Protip::Wrapper.new(request.new, self.class.converter)
            wrapper.assign_attributes request_params
            ExtraMethods.member self, action, method, wrapper.message, response
          end
        else
          define_method action do
            ExtraMethods.member self, action, method, nil, response
          end
        end
      end

      def collection(action:, method:, request: nil, response: nil)
        if request
          define_singleton_method action do |request_params = {}|
            wrapper = ::Protip::Wrapper.new(request.new, converter)
            wrapper.assign_attributes request_params
            ExtraMethods.collection self, action, method, wrapper.message, response
          end
        else
          define_singleton_method action do
            ExtraMethods.collection self, action, method, nil, response
          end
        end
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
      # the resource needs to call its own setters so that fields get marked as dirty
      attributes.each { |field_name, value| send("#{field_name}=", value) }
      nil # return nil to match ActiveRecord behavior
    end

    def message=(message)
      @wrapper = Protip::Wrapper.new(message, self.class.converter)
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

    private

    # needed for ActiveModel::Dirty
    def changes_applied
      @previously_changed = changes
      @changed_attributes.clear
    end
  end
end
