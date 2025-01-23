require 'test_helper'

require 'protip/client'
require 'protip/resource'

module Protip::ResourceTest # Namespace for internal constants
  describe Protip::Resource do
    let :pool do
      # See https://github.com/google/protobuf/blob/master/ruby/tests/generated_code.rb for
      # examples of field types you can add here
      pool = Google::Protobuf::DescriptorPool.new
      pool.build do
        add_enum 'number' do
          value :ZERO, 0
          value :ONE, 1
        end
        add_message 'nested_message' do
          optional :number, :int64, 1
        end
        add_message 'google.protobuf.BoolValue' do
          optional :value, :bool, 1
        end
        add_message 'resource_message' do
          optional :id, :int64, 1
          optional :string, :string, 2
          optional :string2, :string, 3
          optional :nested_message, :message, 4, 'nested_message'
          optional :number, :enum, 5, 'number'
          repeated :numbers, :enum, 6, 'number'
          optional :boolean, :bool, 8
          repeated :booleans, :bool, 9
          optional :google_bool_value, :message, 10, 'google.protobuf.BoolValue'
          repeated :google_bool_values, :message, 11, 'google.protobuf.BoolValue'

          oneof :oneof_group do
            optional :oneof_string1, :string, 12
            optional :oneof_string2, :string, 13
          end

          optional :double_nested_message, :message, 14, 'double_nested_message'
        end

        add_message 'double_nested_message' do
          optional :nested_message, :message, 1, 'nested_message'
        end

        add_message 'resource_query' do
          optional :param, :string, 1
          optional :nested_message, :message, 2, 'nested_message'
        end

        # Give these things a different structure than resource_query_class,
        # just to avoid any possibility of decoding as the incorrect
        # type but still yielding correct results.
        add_message 'action_query' do
          optional :param, :string, 4
          optional :nested_message, :message, 5, 'nested_message'
        end
        add_message 'action_response' do
          optional :response, :string, 3
        end

      end
      pool
    end
    %w(nested_message resource_message resource_query action_query action_response double_nested_message).each do |name|
      let(:"#{name}_class") do
        pool.lookup(name).msgclass
      end
    end
    let(:nested_message_field) { resource_message_class.descriptor.lookup('nested_message') }
    # Stubbed API client
    let :client do
      mock.responds_like_instance_of(Class.new { include Protip::Client })
    end

    # Call `resource_class` to get an empty resource type.
    let :resource_class do
      resource_class = Class.new do
        include Protip::Resource
        self.base_path = 'base_path'
        class << self
          attr_accessor :client
        end
      end
      resource_class.client = client
      resource_class
    end

    describe '.resource' do

      let :transformer do
        Class.new do
          include Protip::Transformer
        end.new
      end
      describe 'with basic resource' do
        before do
          resource_class.class_exec(transformer, resource_message_class) do |transformer, message|
            resource actions: [], message: message
            self.transformer = transformer
          end
        end

        it 'can only be invoked once' do
          assert_raises RuntimeError do
            resource_class.class_exec(resource_message_class) do |message|
              resource actions: [], message: message
            end
          end
        end

        it 'defines accessors for the fields on its message' do
          resource = resource_class.new
          [:id, :string].each do |method|
            assert_respond_to resource, method
          end
          refute_respond_to resource, :foo
        end

        it 'defines accessors for oneof groups on its message' do
          resource = resource_class.new
          group_name = 'oneof_group'
          assert resource.message.class.descriptor.lookup_oneof(group_name)
          assert_respond_to resource, group_name
        end

        it 'returns nil if the oneof group accessor called when the underlying fields are not set' do
          resource = resource_class.new
          assert_nil resource.oneof_group
        end

        it 'returns the active oneof field when a oneof group accessor is called' do
          resource = resource_class.new
          resource.oneof_string1 = 'foo'
          assert_equal 'foo', resource.oneof_group
          resource.oneof_string2 = 'bar'
          assert_equal 'bar', resource.oneof_group
          resource.oneof_string2 = 'bar'
          resource.oneof_string1 = 'foo'
          assert_equal 'foo', resource.oneof_group
        end

        it 'sets fields on the underlying message when simple setters are called' do
          resource = resource_class.new
          resource.string = 'intern'
          assert_equal 'intern', resource.message.string
          assert_equal 'intern', resource.string
        end

        it 'never checks with the transformer when setting simple types' do
          transformer.expects(:to_message).never
          resource = resource_class.new
          resource.string = 'intern'
        end

        it 'transforms message types to and from their Ruby values' do
          transformer.expects(:to_message).
            once.
            with(6, nested_message_field).
            returns(nested_message_class.new number: 100)
          transformer.expects(:to_object).
            at_least_once.
            with(nested_message_class.new(number: 100), nested_message_field).
            returns 'intern'

          resource = resource_class.new
          resource.nested_message = 6

          assert_equal nested_message_class.new(number: 100), resource.message.nested_message, 'object was not converted'
          assert_equal 'intern', resource.nested_message, 'message was not converted'
        end

        describe '(query methods)' do
          let(:resource) { resource_class.new }
          it 'defines query methods for the scalar enums on its message' do
            assert_respond_to resource, :number?
            assert resource.number?(:ZERO)
            refute resource.number?(:ONE)
          end

          it 'defines query methods for the primitives on its message' do
            resource.boolean = true
            assert_respond_to resource, :boolean?
            assert_equal true, resource.boolean?
          end

          it 'defines query methods for the submessages on its message' do
            assert_respond_to resource, :google_bool_value?
            assert_equal false, resource.google_bool_value?
          end

          it 'defines query methods for repeated fields' do
            assert_respond_to resource, :numbers?
            assert_equal false, resource.numbers?
          end
        end
      end
      describe 'with empty nested resources' do
        it 'does not throw an error' do
          resource_class.class_exec(resource_message_class) do |message|
            resource actions: [], message: message, nested_resources: {}
          end
        end
      end

      describe 'with invalid nested resource key' do
        it 'throws an error' do
          assert_raises RuntimeError do
            resource_class.class_exec(resource_message_class) do |message|
              resource actions: [],
                message: message,
                nested_resources: {'snoop' => Protip::Resource}
            end
          end
        end
      end

      describe 'with invalid nested resource class' do
        it 'throws an error' do
          assert_raises RuntimeError do
            resource_class.class_exec(resource_message_class) do |message|
              resource actions: [], message: message, nested_resources: {dogg: Object}
            end
          end
        end
      end

    end

    # index/find/member/collection actions should all convert more complex Ruby objects to submessages in their
    # queries
    def self.it_converts_query_parameters
      before do
        # Sanity check - the user should specify all these variables
        # in "let" statements http_method, path, query_class, and
        # response specify the expected call to the client
        # nested_message_field_name specifies the field on the query
        # class that may or may not be convertible, and should refer
        # to a submessage field of type nested_message_class
        # invoke_method! should call the desired method, assuming that
        # +parameters+ contains the query parameters to pass in
        # (e.g. `resource_class.all(parameters)` or
        # `resource_class.find('id', parameters)`)
        %i(
          http_method
          path
          query_class
          response
          nested_message_field_name
          invoke_method!
        ).each do |name|
          raise "Must define #{name} before invoking `it_converts_query_parameters`" unless respond_to?(name)
        end

        # All tests expect the same HTTP call
        client.expects(:request)
          .once
          .with(method: http_method, path: path,
            message: query_class.new(:"#{nested_message_field_name}" => nested_message_class.new(number: 43)),
            response_type: (nil == response ? nil : response.class),
          ).returns(response)
      end

      describe 'with a transformable object as one of the attributes' do
        before do
          resource_class.transformer.stubs(:to_message)
            .with(42, query_class.descriptor.lookup(nested_message_field_name.to_s))
            .returns(nested_message_class.new(number: 43))
        end

        let(:parameters) { {"#{nested_message_field_name}" => 42} }
        it 'transforms query parameters' do
          invoke_method!
        end
      end

      describe 'with a submessage as one of the attributes' do
        let(:parameters) { {"#{nested_message_field_name}" => nested_message_class.new(number: 43)} }
        it 'allows a submessage to be provided directly' do
          invoke_method!
        end
      end

      describe 'with a message as the main argument' do
        let(:parameters) do
          query_class.new(
            :"#{nested_message_field_name}" => nested_message_class.new(number: 43)
          )
        end
        it 'allows a complete message to be provided directly' do
          invoke_method!
        end
      end
    end


    describe '.all' do
      let :response do
        Protip::Messages::Array.new({
          messages: [
            resource_message_class.new(string: 'banjo', id: 1),
            resource_message_class.new(string: 'kazooie', id: 2),
          ].map{|m| resource_message_class.encode(m)}
        })
      end

      it 'does not exist if the resource has not been defined' do
        refute_respond_to resource_class, :all
      end

      it 'does not exist if the resource is defined without the index action' do
        resource_class.class_exec(resource_message_class) do |message|
          resource actions: [:show], message: message
        end
        refute_respond_to resource_class, :all
      end

      describe 'without a query' do
        before do
          resource_class.class_exec(resource_message_class) do |message|
            resource actions: [:index], message: message
          end
        end

        it 'requests an array from the index URL' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Get, path: 'base_path', message: nil, response_type: Protip::Messages::Array)
            .returns(response)
          resource_class.all
        end

        it 'fails if we try to pass in a query' do
          assert_raises ArgumentError do
            resource_class.all(query: 'param')
          end
        end

        # Doesn't matter whether we have a query or not
        it 'parses the response into an array of resources' do
          client.stubs(:request).returns(response)
          results = resource_class.all

          assert_equal 2, results.length
          results.each { |result| assert_instance_of resource_class, result }

          assert_equal 'banjo', results[0].string
          assert_equal 1, results[0].id

          assert_equal 'kazooie', results[1].string
          assert_equal 2, results[1].id
        end

        # Doesn't matter whether we have a query or not
        it 'allows an empty array' do
          client.stubs(:request).returns(Protip::Messages::Array.new)
          results = resource_class.all

          assert_equal [], results
        end
      end

      describe 'with a query' do
        before do
          resource_class.class_exec(resource_message_class, resource_query_class) do |message, query|
            resource actions: [:index], message: message, query: query
          end
        end

        it 'requests an array from the index URL with the query' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Get, path: 'base_path',
              message: resource_query_class.new(param: 'val'), response_type: Protip::Messages::Array
            ).returns(response)
          resource_class.all(param: 'val')
        end

        it 'allows a request with an empty query' do
          client.expects(:request)
            .with(method: Net::HTTP::Get, path: 'base_path',
              message: resource_query_class.new, response_type: Protip::Messages::Array)
          .returns(response)
          resource_class.all
        end

        describe '(convertibility)' do
          let(:http_method) { Net::HTTP::Get }
          let(:path) { 'base_path' }
          let(:query_class) { resource_query_class }
          let(:nested_message_field_name) { :nested_message }
          let(:invoke_method!) { resource_class.all(parameters) }
          it_converts_query_parameters
        end
      end
    end

    describe '.find' do
      let :response do
        resource_message_class.new(string: 'pitbull', id: 100)
      end

      it 'does not exist if the resource has not been defined' do
        refute_respond_to resource_class, :find
      end

      it 'does not exist if the resource is defined without the show action' do
        resource_class.class_exec(resource_message_class) do |message|
          resource actions: [:index], message: message
        end
        refute_respond_to resource_class, :find
      end

      describe 'without a query' do
        before do
          resource_class.class_exec(resource_message_class) do |message|
            resource actions: [:show], message: message
          end
        end

        it 'requests its message type from the show URL' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Get, path: 'base_path/3', message: nil, response_type: resource_message_class)
            .returns(response)
          resource_class.find 3
        end

        it 'fails if we try to pass in a query' do
          assert_raises ArgumentError do
            resource_class.find 2, param: 'val'
          end
        end

        # Doesn't matter whether we have a query or not
        it 'parses the response message into a resource' do
          client.stubs(:request).returns(response)
          resource = resource_class.find 100
          assert_instance_of resource_class, resource

          assert_equal 100, resource.id
          assert_equal 'pitbull', resource.string
        end
      end

      describe 'with a query' do
        before do
          resource_class.class_exec(resource_message_class, resource_query_class) do |message, query|
            resource actions: [:show], message: message, query: query
          end
        end

        it 'requests its message type from the show URL with the query' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Get, path: 'base_path/5',
              message: resource_query_class.new(param: 'val'), response_type: resource_message_class)
            .returns(response)
          resource_class.find 5, param: 'val'
        end

        it 'allows a request with an empty query' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Get, path: 'base_path/6',
              message: resource_query_class.new, response_type: resource_message_class)
            .returns(response)
          resource_class.find 6
        end

        describe '(convertibility)' do
          let(:http_method) { Net::HTTP::Get }
          let(:path) { 'base_path/5' }
          let(:query_class) { resource_query_class }
          let(:nested_message_field_name) { :nested_message }
          let(:invoke_method!) { resource_class.find 5, parameters }
          it_converts_query_parameters
        end
      end
    end

    describe '#initialize' do
      it 'fails if a resource definition has not yet been given' do
        error = assert_raises RuntimeError do
          resource_class.new
        end
        assert_equal 'Must define a message class using `resource`', error.message
      end
      describe 'when a message is given' do
        before do
          resource_class.class_exec(resource_message_class) do |message|
            resource actions: [], message: message
          end
        end

        it 'creates a resource with an empty message if no attributes are provided' do
          assert_equal resource_message_class.new, resource_class.new.message
        end

        it 'allows a message to be provided directly' do
          message = resource_message_class.new(id: 1)
          assert_equal message, resource_class.new(message).message
        end

        it 'sets attributes when a hash is given' do
          attrs = {id: 2}
          assert_equal resource_message_class.new(attrs), resource_class.new(attrs).message
        end

        it 'allows nested attributes to be given' do
          attrs = {
            nested_message: {
              number: 3
            }
          }
          assert_equal nested_message_class.new(number: 3), resource_class.new(attrs).message.nested_message
        end
      end
    end

    # Shared behavior for direct setters and #assign_attributes. The setter object must be able to be
    # initialized as +setter_class.new(resource)+, and must respond to +setter.set({field => value, field2 => value2})+
    # by performing the appropriate operation (e.g. +.field=+ or +.assign_attributes+).
    def self.describe_dirty_attributes_setter(setter_class)

      describe 'dirty attributes' do
        let(:transformer) do
          mock.responds_like_instance_of(Class.new { include Protip::Transformer })
        end
        let :resource do
          resource_class.new resource_message_class.new({
            string: 'foo',
            nested_message: nested_message_class.new(number: 32)
          })
        end

        let :setter do
          setter_class.new(resource)
        end

        before do
          resource_class.transformer = transformer
          raise 'sanity check failed' if resource.changed? || resource.string_changed? || resource.nested_message_changed?
        end

        it 'recognizes changes in scalar values' do
          setter.set string: 'bar'
          assert resource.changed?, 'resource was not marked as changed'
          assert resource.string_changed?, 'field was not marked as changed'
        end

        it 'recognizes when scalar values do not change' do
          setter.set string: 'foo'
          refute resource.changed?, 'resource was marked as changed'
          refute resource.string_changed?, 'field was marked as changed'
        end

        describe '(message attributes)' do
          before do
            transformer.stubs(:to_message).
              with(42, nested_message_field).
              returns(nested_message_class.new(number: 52))

            transformer.stubs(:to_object).
              with(nested_message_class.new(number: 52), nested_message_field).
              returns(42)

            transformer.stubs(:to_object).
              with(nested_message_class.new(number: 62), nested_message_field).
              returns(72)

            transformer.stubs(:to_object).
              # Convert any +double_nested_message+ (with the correct
              # associated field) to the same value, since we don't
              # really care about testing it.
              with do |value, field|
                value.is_a?(double_nested_message_class) &&
                  field.name == 'double_nested_message'
              end.returns(100)
          end
          it 'marks messages as changed if they are changed as Ruby values' do
            setter.set nested_message: 42
            assert resource.changed?, 'resource was not marked as changed'
            assert resource.nested_message_changed?, 'field was not marked as changed'
          end
          it 'marks sub-messages as changed if they are changed as messages' do
            setter.set nested_message: nested_message_class.new(number: 62)
            assert resource.changed?, 'resource was not marked as changed'
            assert resource.nested_message_changed?, 'field was not marked as changed'
          end
          it 'marks sub-messages as changed when they are nullified' do
            setter.set nested_message: nil
            assert resource.changed?, 'resource was not marked as changed'
            assert resource.nested_message_changed?, 'field was not marked as changed'
          end
          it 'recognizes when messages are not changed when set as Ruby values' do
            resource.message.nested_message.number = 52
            raise 'sanity check failed' if resource.changed? || resource.nested_message_changed?
            setter.set nested_message: 42
            refute resource.changed?, 'resource was marked as changed'
            refute resource.string_changed?, 'field was marked as changed'
          end
          it 'recognizes when sub-messages are not changed when set as messages' do
            setter.set nested_message: nested_message_class.new(number: 32)
            refute resource.changed?, 'resource was marked as changed'
            refute resource.string_changed?, 'field was marked as changed'
          end

          # Test that we don't trigger an old protobuf bug when
          # comparing messages with sub-messages that are non-nil on
          # the left, nil on the right. (We used to work around this
          # bug explicitly in our equality check, now just leaving the
          # test in to make sure it doesn't come back.)
          it 'recognizes_when_double-nested_messages_are_changed_to_nil_values' do
            # Initially the field should have its nested message set.
            resource.message.double_nested_message = double_nested_message_class.new(
              nested_message: nested_message_class.new(number: 10)
            )

            # Sanity check
            refute resource.double_nested_message_changed?

            # Then give it a field with a nil nested message to
            # trigger the protobuf bug.
            setter.set double_nested_message: double_nested_message_class.new

            # Sanity check
            assert resource.double_nested_message_changed?
          end
        end
      end
    end


    describe 'attribute writer' do
      before do
        resource_class.class_exec(resource_message_class) do |resource_message_class|
          resource actions: [], message: resource_message_class
        end
      end

      it 'delegates writes to the wrapper object' do
        resource = resource_class.new
        test_string = 'new'
        Protip::Decorator.any_instance.expects(:string=).with(test_string)
        resource.string = test_string
      end

      setter_class = Class.new do
        def initialize(resource) ; @resource = resource ; end
        def set(attributes) ; attributes.each{|attribute, value| @resource.public_send(:"#{attribute}=", value)} ; end
      end
      describe_dirty_attributes_setter(setter_class)
    end

    describe '#assign_attributes' do
      before do
        resource_class.class_exec(resource_message_class) do |resource_message_class|
          resource actions: [], message: resource_message_class
        end
      end

      let :resource do
        resource_class.new
      end

      it 'delegates to #assign_attributes on the wrapper' do
        # Instantiate the resource before setting the expectation, since assign_attributes is allowed to be
        # called during #initialize as well
        resource

        Protip::Decorator.any_instance.expects(:assign_attributes).with(string: 'foo')
        resource.assign_attributes string: 'foo'
      end

      setter_class = Class.new do
        def initialize(resource) ; @resource = resource ; end
        def set(attributes) ; @resource.assign_attributes attributes ; end
      end
      describe_dirty_attributes_setter setter_class

      # This section relies on correct behavior of +Protip.default_transformer+.
      describe 'dirty attributes (nested hashes)' do

        it 'marks nested hashes as changed if they set a new field' do
          resource.assign_attributes nested_message: {number: 52}
          assert resource.changed?, 'resource was not marked as changed'
          assert resource.nested_message_changed?, 'field was not marked as changed'
        end

        describe '(when a nested message has an initial value)' do
          before do
            resource.nested_message = nested_message_class.new(number: 32)
            resource.send(:changes_applied) # Clear the list of changes
            # Sanity check
            raise 'unexpected' if resource.changed? || resource.string_changed? || resource.nested_message_changed?
          end

          it 'marks nested hashes as changed if they change a field' do
            resource.assign_attributes nested_message: {number: 42}
            assert resource.changed?, 'resource was not marked as changed'
            assert resource.nested_message_changed?, 'field was not marked as changed'
          end

          it 'does not mark nested hashes as changed if they do not change the underlying message' do
            resource.assign_attributes nested_message: {number: 32}
            refute resource.changed?, 'resource was marked as changed'
            refute resource.nested_message_changed?, 'field was marked as changed'
          end
        end
      end

      it 'returns nil' do
        assert_nil resource.assign_attributes(string: 'asdf')
      end
    end

    describe '#save' do
      let :response do
        resource_message_class.new(string: 'pit', string2: 'bull', id: 200)
      end

      describe 'for a new record' do
        before do
          resource_class.class_exec(resource_message_class) do |resource_message_class|
            resource actions: [:create], message: resource_message_class
          end
          resource_class.any_instance.stubs(:persisted?).returns(false)
        end

        it 'sends the resource to the server' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Post, path: 'base_path',
              message: resource_message_class.new(string: 'time', string2: 'flees'), response_type: resource_message_class)
            .returns(response)

          # Set via initializer and direct setter
          resource = resource_class.new(string: 'time')
          resource.string2 = 'flees'
          resource.save
        end

        it 'returns true' do
          client.stubs(:request).returns(response)
          resource = resource_class.new string: 'flees'
          assert resource.save, 'save returned false'
        end

        it 'updates its internal message store with the server response' do
          client.stubs(:request).returns(response)
          resource = resource_class.new
          resource.save
          assert_equal response, resource.message
        end

        it 'marks changes as applied' do
          client.stubs(:request).returns(response)
          resource = resource_class.new(string: 'time')
          assert resource.string_changed?, 'string should initially be changed'
          assert resource.save
          assert !resource.string_changed?, 'string should no longer be changed after save'
        end
      end

      describe 'for an existing record' do
        before do
          resource_class.class_exec(resource_message_class) do |resource_message_class|
            resource actions: [:update], message: resource_message_class
          end
          resource_class.any_instance.stubs(:persisted?).returns(true)
        end

        it 'sends the resource to the server' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Put, path: 'base_path/4',
              message: resource_message_class.new(id: 4, string: 'pitbull'), response_type: resource_message_class)
            .returns(response)

          resource = resource_class.new(id: 4, string: 'pitbull')
          resource.save
        end

        it 'returns true' do
          client.stubs(:request).returns(response)
          resource = resource_class.new id: 3
          assert resource.save, 'save returned false'
        end

        it 'updates its internal message store with the server repsonse' do
          client.stubs(:request).returns(response)
          resource = resource_class.new id: 5
          resource.save
          assert_equal response, resource.message
        end

        it 'marks changes as applied' do
          client.stubs(:request).returns(response)
          resource = resource_class.new id: 5, string: 'new_string'
          assert resource.string_changed?, 'string should initially be changed'
          assert resource.save
          assert !resource.string_changed?, 'string should no longer be changed after save'
        end
      end

      describe 'when validation errors are thrown' do
        before do
          # Set up an errors instance variable that we can set actual messages on
          @errors = Protip::Messages::Errors.new

          request = mock
          request.stubs(:uri).returns('http://some.uri')

          response = mock
          response.stubs(status: 500, body: @errors.to_proto)

          exception = Protip::UnprocessableEntityError.new request, response
          exception.stubs(:errors).returns @errors
          client.stubs(:request).raises(exception)

          resource_class.class_exec(resource_message_class) do |resource_message_class|
            resource actions: [:update, :create], message: resource_message_class
          end
          @resource = resource_class.new
        end

        it 'parses base errors' do
          @errors.messages += ['message1', 'message2']
          @resource.save

          assert_equal ['message1', 'message2'], @resource.errors['base']
        end

        it 'parses field errors' do
          [
            Protip::Messages::FieldError.new(field: 'string', message: 'message1'),
            Protip::Messages::FieldError.new(field: 'id', message: 'message2'),
            Protip::Messages::FieldError.new(field: 'string', message: 'message3'),
          ].each{|field_error| @errors.field_errors.push field_error}
          @resource.save

          assert_equal ['message1', 'message3'], @resource.errors['string']
          assert_equal ['message2'], @resource.errors['id']
        end

        it 'returns false' do
          refute @resource.save, 'save returned true'
        end

        it 'does not mark changes as applied' do
          @resource.string = 'new_string'
          assert @resource.string_changed?, 'string should initially be changed'
          refute @resource.save
          assert @resource.string_changed?, 'string should still be changed after unsuccessful save'
        end
      end
    end

    describe '#destroy' do
      describe 'for an existing record' do
        let :response do
          resource_message_class.new(id: 5, string: 'deleted')
        end
        before do
          resource_class.class_exec(resource_message_class) do |resource_message_class|
            resource actions: [:destroy], message: resource_message_class
          end
          resource_class.any_instance.stubs(:persisted?).returns(true)
        end

        it 'sends a delete request to the server' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Delete, path: 'base_path/79', message: nil, response_type: resource_message_class)
            .returns(response)
          resource_class.new(id: 79).destroy
        end

        it 'updates its internal message with the server response' do
          client.stubs(:request).returns(response)
          resource = resource_class.new(id: 80)

          resource.destroy
          assert_equal response, resource.message
        end
      end
    end

    # member/collection have almost the same behavior, except for the URL and the target on which they're
    # called. We assume that a `let(:target)` block has already been defined, which will yield the receiver
    # of the non-resourceful method to be defined (e.g. a resource instance or resource class).
    #
    # @param defining_method [String] member or collection, e.g. the method to call in a `class_val` block
    # @param path [String] the URI that the client should expect to receive for an action of this type
    #   named 'action'
    def self.describe_non_resourceful_action(defining_method, path)

      # let(:target) is assumed to have been defined

      let :response do
        action_response_class.new(response: 'bilbo')
      end

      before do
        resource_class.class_exec(resource_message_class) do |resource_message_class|
          resource actions: [], message: resource_message_class
        end
      end
      describe 'without a request or response type' do
        before do
          resource_class.class_eval do
            send defining_method, action: :action, method: Net::HTTP::Put
          end
        end

        it 'sends a request with no body and no response type to the expected endpoint' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Put, path: path, message: nil, response_type: nil)
            .returns(nil)
          target.action
        end

        it 'does not accept request parameters' do
          assert_raises ArgumentError do
            target.action param: 'val'
          end
        end

        it 'returns nil' do
          client.stubs(:request).returns(nil)
          assert_nil target.action
        end
      end
      describe 'with a request type' do
        before do
          resource_class.class_exec(action_query_class) do |request|
            send defining_method, action: :action, method: Net::HTTP::Post, request: request
          end
        end

        let(:response) { nil }

        it 'sends a request with a body to the expected endpoint' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Post, path: path,
              message: action_query_class.new(param: 'tom cruise'), response_type: nil)
            .returns(nil)
          target.action param: 'tom cruise'
        end

        it 'allows a request with no parameters' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Post, path: path,
              message: action_query_class.new, response_type: nil)
            .returns(nil)
          target.action
        end

        describe '(convertibility)' do
          let(:http_method) { Net::HTTP::Post }
          let(:path) { path }
          let(:query_class) { action_query_class }
          let(:nested_message_field_name) { :nested_message }
          let(:invoke_method!) { target.action(parameters) }
          it_converts_query_parameters
        end
      end

      describe 'with a response type' do
        before do
          resource_class.class_exec(action_response_class) do |response|
            send defining_method, action: :action, method: Net::HTTP::Get, response: response
          end
        end

        it 'sends a request with a specified response type to the expected endpoint' do
          client.expects(:request)
            .once
            .with(method: Net::HTTP::Get, path: path,
              message: nil, response_type: action_response_class)
            .returns(response)
          target.action
        end

        it 'returns the wrapped server response' do
          client.stubs(:request).returns(response)
          assert_equal Protip::Decorator.new(response, resource_class.transformer), target.action
        end
      end
    end

    describe '.member' do
      let :target do
        resource_class.new id: 42
      end
      describe_non_resourceful_action 'member', 'base_path/42/action'
    end

    describe '.collection' do
      let :target do
        resource_class
      end
      describe_non_resourceful_action 'collection', 'base_path/action'
    end

    # Common tests for both types of belongs_to association. Assumes a `let(:association)` statement
    # has been provided, to give a mock of the appropriate association with `define_accessors!` stubbed out
    # If a block is needed to run the method, it can be provided
    def self.describe_association_method!(method, association_class, &block)
      describe '(common behvaior)' do
        it 'defines accessors' do
          association_class.expects(:new).once.returns(association)
          association.expects(:define_accessors!).once
          resource_class.class_exec(method) { |method| send method, :association_name, &block }
        end

        it 'returns the created association' do
          association_class.expects(:new).once.returns(association)
          resource_class.class_exec(method) { |method |@result = send method, :association_name, &block }
          assert_equal association, resource_class.instance_variable_get(:'@result'), 'association was not returned'
        end

        it 'stores the created association' do
          association_class.expects(:new).once.returns(association)
          resource_class.class_exec(method) { |method| send method, :association_name, &block }
          assert_includes resource_class.public_send(:"#{method}_associations"), association
        end

        it 'initializes the set of associations to the empty set' do
          stored_associations = resource_class.public_send(:"#{method}_associations")
          assert_instance_of Set, stored_associations
          assert_empty stored_associations
        end

        it 'raises an error on invalid options' do
          error = assert_raises ArgumentError do
            resource_class.class_exec(method) do |method|
              send method, :association_name, bad_option: 'bad', &block
            end
          end
          assert_match(/bad_option/, error.message)
        end
      end
    end

    describe '.belongs_to' do
      let :association do
        association = mock.responds_like_instance_of Protip::Resource::Associations::BelongsToAssociation
        association.stubs(:define_accessors!)
        association
      end

      it 'creates a belongs_to association and passes in options' do
        Protip::Resource::Associations::BelongsToAssociation.expects(:new).once
          .with(resource_class, :association_name, class_name: 'Foo')
          .returns(association)
        resource_class.class_eval { belongs_to :association_name, class_name: 'Foo' }
      end

      describe_association_method! :belongs_to, Protip::Resource::Associations::BelongsToAssociation
    end

    describe '.belongs_to_polymorphic' do
      let :association do
        association = mock.responds_like_instance_of Protip::Resource::Associations::BelongsToPolymorphicAssociation
        association.stubs(:define_accessors!)
        association
      end

      it 'creates a polymorphic belongs_to association, passing in nested associations from its yielded block' do
        nested_association = mock.responds_like_instance_of Protip::Resource::Associations::BelongsToAssociation
        resource_class.expects(:belongs_to).once.with(:foo).returns(nested_association)

        Protip::Resource::Associations::BelongsToPolymorphicAssociation.expects(:new).once
          .with(resource_class, :bar, [nested_association], id_field: 'field').returns(association)

        resource_class.class_eval do
          belongs_to_polymorphic :bar, id_field: 'field' do
            belongs_to :foo
          end
        end
      end

      describe_association_method!(:belongs_to_polymorphic,
        Protip::Resource::Associations::BelongsToPolymorphicAssociation) { }
    end

    describe '.transformer' do
      describe 'default value' do
        it 'defaults to the default transformer' do
          assert_same Protip.default_transformer, resource_class.transformer
        end
      end
    end
  end
end
