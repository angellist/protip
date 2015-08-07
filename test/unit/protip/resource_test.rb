require 'test_helper'

require 'protip/client'
require 'protip/converter'
require 'protip/resource'

module Protip::ResourceTest # Namespace for internal constants
  describe Protip::Resource do
    let :pool do
      pool = Google::Protobuf::DescriptorPool.new
      pool.build do
        add_message 'nested_message' do
          optional :number, :int64, 1
        end
        add_message 'resource_message' do
          optional :id, :int64, 1
          optional :string, :string, 2
          optional :string2, :string, 3
          optional :nested_message, :message, 4, 'nested_message'
        end

        add_message 'resource_query' do
          optional :param, :string, 1
        end

        # Give these things a different structure than resource_query_class,
        # just to avoid any possibility of decoding as the incorrect
        # type but still yielding correct results.
        add_message 'action_query' do
          optional :param, :string, 4
        end
        add_message 'action_response' do
          optional :response, :string, 3
        end

      end
      pool
    end
    %w(nested_message resource_message resource_query action_query action_response).each do |name|
      let(:"#{name}_class") do
        pool.lookup(name).msgclass
      end
    end
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

      let :converter do
        Class.new do
          include Protip::Converter
        end.new
      end

      before do
        resource_class.class_exec(converter, resource_message_class) do |converter, message|
          resource actions: [], message: message
          self.converter = converter
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

      it 'sets fields on the underlying message when simple setters are called' do
        resource = resource_class.new
        resource.string = 'intern'
        assert_equal 'intern', resource.message.string
        assert_equal 'intern', resource.string
      end

      it 'never checks with the converter when setting simple types' do
        converter.expects(:convertible?).never
        resource = resource_class.new
        resource.string = 'intern'
      end

      it 'checks with the converter when setting message types' do
        converter.expects(:convertible?).once.with(nested_message_class).returns(false)
        resource = resource_class.new
        assert_raises(ArgumentError) do
          resource.nested_message = 5
        end
      end

      it 'converts message types to and from their Ruby values when the converter allows' do
        converter.expects(:convertible?).times(2).with(nested_message_class).returns(true)
        converter.expects(:to_message).once.with(6, nested_message_class).returns(nested_message_class.new number: 100)
        converter.expects(:to_object).once.with(nested_message_class.new number: 100).returns 'intern'

        resource = resource_class.new
        resource.nested_message = 6

        assert_equal nested_message_class.new(number: 100), resource.message.nested_message, 'object was not converted'
        assert_equal 'intern', resource.nested_message, 'message was not converted'
      end
    end

    describe '.all' do
      let :response do
        Protip::Messages::Array.new({
          messages: [
            resource_message_class.new(string: 'banjo', id: 1),
            resource_message_class.new(string: 'kazooie', id: 2),
          ].map{|m| resource_message_class.encode(m).encode('UTF-8')}
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

        it 'delegates to #assign_attributes on its wrapper object when a hash is given' do
          attrs = {id: 3}
          Protip::Wrapper.any_instance.expects(:assign_attributes).once.with({id: 3})
          resource_class.new(attrs)
        end
      end
    end

    describe '#assign_attributes' do
      before do
        resource_class.class_exec(resource_message_class) do |resource_message_class|
          resource actions: [], message: resource_message_class
        end
      end
      it 'delegates to #assign_attributes on its wrapper object' do
        resource = resource_class.new

        Protip::Wrapper.any_instance.expects(:assign_attributes).once.with(string: 'whodunnit').returns('boo')
        assert_equal 'boo', resource.assign_attributes(string: 'whodunnit')
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
      end

      describe 'when validation errors are thrown' do
        before do
          # Set up an errors instance variable that we can set actual messages on
          @errors = Protip::Messages::Errors.new

          exception = Protip::UnprocessableEntityError.new mock, mock
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

        it 'returns the server response' do
          client.stubs(:request).returns(response)
          assert_equal response, target.action
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

    describe '.converter' do
      describe 'default value' do
        it 'defaults to the standard converter' do
          assert_instance_of Protip::StandardConverter, resource_class.converter
        end

        it 're-uses the same converter on repeated accesses' do
          assert_same resource_class.converter, resource_class.converter
        end
      end
    end
  end
end
