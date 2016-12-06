require 'test_helper'

require 'protip'
require 'google/protobuf/wrappers'

describe 'Protip::Resource (functional)' do

  before do
    WebMock.disable_net_connect!
  end

  let :pool do
    pool = Google::Protobuf::DescriptorPool.new
    pool.build do
      add_message 'google.protobuf.Int64Value' do # TODO: can we get this directly into the pool from the global pool?
        optional :value, :int64, 1
      end

      # Make sure none of these are structurally identical (e.g. give fields
      # different positions), to avoid potential errors where a message is
      # incorrectly encoded but still accidentally correctly decoded.

      add_message 'nested_message' do
        optional :inconvertible_value, :string, 1
      end
      add_message 'resource_message' do
        optional :id, :message, 2, 'google.protobuf.Int64Value'
        optional :ordered_tests, :string, 3
        optional :nested_message, :message, 4, 'nested_message'
        optional :nested_int, :message, 5, 'google.protobuf.Int64Value'
        optional :association_id, :message, 6, 'google.protobuf.Int64Value'
      end

      add_message 'resource_query' do
        optional :param, :string, 7
      end

      add_message 'name_response' do
        optional :name, :string, 8
      end

      add_message 'search_request' do
        optional :term, :string, 9
      end

      add_message 'search_response' do
        repeated :results, :string, 10
      end

      add_message 'fetch_request' do
        repeated :names, :string, 11
      end
    end
    pool
  end
  %w(nested_message resource_message resource_query name_response search_request search_response fetch_request).each do |name|
    let(:"#{name}_class") do
      pool.lookup(name).msgclass
    end
  end
  let :int_message_class do
    pool.lookup('google.protobuf.Int64Value').msgclass
  end

  let :client_class do
    Class.new do
      include Protip::Client
      def base_uri
        'https://external.service'
      end
    end
  end

  let :resource_class do
    resource_class = Class.new do
      include Protip::Resource
    end
    resource_class.class_exec(resource_query_class, resource_message_class, name_response_class, search_request_class, search_response_class, fetch_request_class, client_class) do |resource_query_class, resource_message_class, name_response_class, search_request_class, search_response_class, fetch_request_class, client_class|
      resource actions: [:index, :show, :create, :update, :destroy],
               query: resource_query_class, message: resource_message_class

      member action: :archive, method: Net::HTTP::Put
      member action: :name, method: Net::HTTP::Get, response: name_response_class

      collection action: :search, method: Net::HTTP::Get, request: search_request_class, response: search_response_class
      collection action: :fetch, method: Net::HTTP::Post, request: fetch_request_class

      self.base_path = 'resources'
      self.client = client_class.new
    end
    resource_class
  end

  describe '.all' do
    describe 'with a successful server response' do
      before do
        # If this is erroring out, change :string to :bytes in array.rb - the Ruby compiler currently compiles
        # incorrectly.
        response = Protip::Messages::Array.new(messages: ['bilbo', 'baggins'].each_with_index.map do |name, index|
          message = resource_message_class.new(id: int_message_class.new(value: index), ordered_tests: name, nested_int: int_message_class.new(value: index + 42))
          message.class.encode(message)
        end)
        stub_request(:get, 'https://external.service/resources')
          .to_return body: response.class.encode(response)
      end

      it 'requests resources from the index endpoint' do
        results = resource_class.all param: 'val'

        assert_requested :get, 'https://external.service/resources',
          times: 1, body: resource_query_class.encode(resource_query_class.new(param: 'val'))

        assert_equal 2, results.length, 'incorrect number of resources were returned'
        results.each { |result| assert_instance_of resource_class, result, 'incorrect type was parsed'}

        assert_equal(
          {
            'ordered_tests' => 'bilbo', 'id' => 0, 'nested_message' => nil, 'nested_int' => 42, 'association_id' => nil
          },
          results[0].attributes
        )
        assert_equal(
          {
            'ordered_tests' => 'baggins', 'id' => 1, 'nested_message' => nil, 'nested_int' => 43,
            'association_id' => nil
          },
          results[1].attributes
      )
      end

      it 'allows requests without parameters' do
        results = resource_class.all
        assert_requested :get, 'https://external.service/resources',
          times: 1, body: resource_query_class.encode(resource_query_class.new)
        assert_equal 2, results.length, 'incorrect number of resources were returned'
      end
    end
  end

  describe '.find' do
    describe 'with a successful server response' do
      before do
        message = resource_message_class.new(id: int_message_class.new(value: 311), ordered_tests: 'i_suck_and_my_tests_are_order_dependent!')
        response = message.class.encode(message)
        stub_request(:get, 'https://external.service/resources/311').to_return body: response.encode
      end

      it 'requests the resource from the show endpoint' do
        resource = resource_class.find 311, param: 'val'
        assert_requested :get, 'https://external.service/resources/311', times: 1,
          body: resource_query_class.encode(resource_query_class.new(param: 'val'))
        assert_instance_of resource_class, resource
        assert_equal 311, resource.id
        assert_equal 'i_suck_and_my_tests_are_order_dependent!', resource.ordered_tests
      end

      it 'allows requests without parameters' do
        resource = resource_class.find 311
        assert_requested :get, 'https://external.service/resources/311', times: 1,
          body: resource_query_class.encode(resource_query_class.new)
        assert_equal 'i_suck_and_my_tests_are_order_dependent!', resource.ordered_tests
      end
    end
  end

  describe '#save' do
    let :resource_message do
      resource_message_class.new(id: int_message_class.new(value: 666), ordered_tests: 'yes')
    end
    let :errors_message do
      Protip::Messages::Errors.new({
        messages: ['base1', 'base2'],
        field_errors: [
          Protip::Messages::FieldError.new(field: 'ordered_tests', message: 'are not OK')
        ]
      })
    end

    # Create and update cases are similar - we just modify the ID attribute on
    # the initial resource, the HTTP method, and the expected URL.
    [
      [nil, :post, 'https://external.service/resources'],
      [666, :put, 'https://external.service/resources/666']
    ].each do |id, method, uri|
      describe "with a #{id ? 'persisted' : 'non-persisted'} resource" do
        before do
          attrs = {nested_int: 100}
          if id
            attrs[:id] = id
          end
          @resource = resource_class.new attrs
        end

        describe 'with a successful server response' do
          before do
            stub_request(method, uri).to_return body: resource_message.class.encode(resource_message)
          end

          it 'returns true' do
            assert @resource.save, 'save was not successful'
          end

          it 'saves the resource and parses the server response' do
            @resource.ordered_tests = 'no'
            @resource.save

            attrs = {ordered_tests: 'no', nested_int: int_message_class.new(value: 100)}
            if id
              attrs[:id] = int_message_class.new(value: id)
            end
            message = resource_message_class.new(attrs)
            assert_requested method, uri,
              times: 1, body: message.class.encode(message)
            assert_equal 'yes', @resource.ordered_tests
          end
        end

        describe 'with a 422 server response' do
          before do
            stub_request(method, uri)
              .to_return body: errors_message.class.encode(errors_message), status: 422
          end

          it 'returns false' do
            refute @resource.save, 'save appeared successful'
          end

          it 'adds errors based on the server response' do
            @resource.save
            assert_equal ['base1', 'base2'], @resource.errors['base']
            assert_equal ['are not OK'], @resource.errors['ordered_tests']
          end
        end
      end
    end
  end

  describe '.member' do
    # TODO
  end

  describe '.collection' do
    # TODO
  end

  describe '.belongs_to' do
    before do
      resource_class.class_eval do
        belongs_to :association, class_name: 'ResourceClass', id_field: :association_id
      end
    end

    it 'returns nil when no association ID has been set' do
      Object.stub_const(:ResourceClass, resource_class) do
        resource_class.expects(:find).never
        assert_nil resource_class.new.association
      end
    end

    it 'fetches the associated resource' do
      Object.stub_const(:ResourceClass, resource_class) do
        associated = mock
        resource_class.expects(:find).once.with(123).returns(associated)
        assert_equal associated, resource_class.new(association_id: 123).association
      end
    end

    it 'allows writing the associated resource' do
      Object.stub_const(:ResourceClass, resource_class) do
        associated = resource_class.new
        associated.id = 5
        base = resource_class.new
        base.association = associated
        assert_equal 5, base.association_id
      end
    end
  end

  describe '.belongs_to_polymorphic' do
    # TODO
  end
end
