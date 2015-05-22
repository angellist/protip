require 'test_helper'

require 'protip'

module Protip::ResourceTestFunctional # Namespace for internal constants
  describe 'Protip::Resource (functional)' do

    before do
      WebMock.disable_net_connect!
    end

    # Make sure none of these are structurally identical (e.g. give fields
    # different positions), to avoid potential errors where a message is
    # incorrectly encoded but still accidentally correctly decoded.
    class NestedMessage < ::Protobuf::Message
      optional :string, :inconvertible_value, 1
    end
    class ResourceMessage < ::Protobuf::Message
      optional :int64, :id, 2
      optional :string, :ordered_tests, 3
      optional NestedMessage, :nested_message, 4
      optional Protip::Int64Value, :nested_int, 5
    end

    class ResourceQuery < ::Protobuf::Message
      optional :string, :param, 6
    end

    class NameResponse < ::Protobuf::Message
      optional :string, :name, 7
    end

    class SearchRequest < ::Protobuf::Message
      optional :string, :term, 8
    end

    class SearchResponse < ::Protobuf::Message
      repeated :string, :results, 9
    end

    class FetchRequest < ::Protobuf::Message
      repeated :string, :names, 10
    end

    class Client
      include Protip::Client
      def base_uri
        'https://external.service'
      end
    end

    class Resource
      include Protip::Resource
      resource actions: [:index, :show, :create, :update, :destroy],
               query: ResourceQuery, message: ResourceMessage

      member action: :archive, method: Net::HTTP::Put
      member action: :name, method: Net::HTTP::Get, response: NameResponse

      collection action: :search, method: Net::HTTP::Get, request: SearchRequest, response: SearchResponse
      collection action: :fetch, method: Net::HTTP::Post, request: FetchRequest

      self.base_path = 'resources'
      self.client = Client.new
    end

    describe '.all' do
      describe 'with a successful server response' do
        before do
          response = Protip::Messages::Array.new(messages: ['bilbo', 'baggins'].each_with_index.map do |name, index|
            ResourceMessage.new(id: index, ordered_tests: name, nested_int: {value: index + 42}).encode
          end)
          stub_request(:get, 'https://external.service/resources')
            .to_return body: response.encode
        end

        it 'requests resources from the index endpoint' do
          results = Resource.all param: 'val'

          assert_requested :get, 'https://external.service/resources',
            times: 1, body: ResourceQuery.new(param: 'val').encode

          assert_equal 2, results.length, 'incorrect number of resources were returned'
          results.each { |result| assert_instance_of Resource, result, 'incorrect type was parsed'}

          assert_equal({ordered_tests: 'bilbo', id: 0, nested_message: nil, nested_int: 42},
            results[0].attributes)
          assert_equal({ordered_tests: 'baggins', id: 1, nested_message: nil, nested_int: 43},
            results[1].attributes)
        end

        it 'allows requests without parameters' do
          results = Resource.all
          assert_requested :get, 'https://external.service/resources',
            times: 1, body: ResourceQuery.new.encode
          assert_equal 2, results.length, 'incorrect number of resources were returned'
        end
      end
    end

    describe '.find' do
      describe 'with a successful server response' do
        before do
          response = ResourceMessage.new(id: 311, ordered_tests: 'i_suck_and_my_tests_are_order_dependent!').encode
          stub_request(:get, 'https://external.service/resources/311').to_return body: response.encode
        end

        it 'requests the resource from the show endpoint' do
          resource = Resource.find 311, param: 'val'
          assert_requested :get, 'https://external.service/resources/311', times: 1,
            body: ResourceQuery.new(param: 'val').encode
          assert_instance_of Resource, resource
          assert_equal 311, resource.id
          assert_equal 'i_suck_and_my_tests_are_order_dependent!', resource.ordered_tests
        end

        it 'allows requests without parameters' do
          resource = Resource.find 311
          assert_requested :get, 'https://external.service/resources/311', times: 1,
            body: ResourceQuery.new.encode
          assert_equal 'i_suck_and_my_tests_are_order_dependent!', resource.ordered_tests
        end
      end
    end

    describe '#save' do
      let :resource_message do
        ResourceMessage.new(id: 666, ordered_tests: 'yes')
      end
      let :errors_message do
        Protip::Messages::Errors.new({
          messages: ['base1', 'base2'],
          field_errors: [
            {field: 'ordered_tests', message: 'are not OK'}
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
            @resource = Resource.new id: id, nested_int: 100
          end

          describe 'with a successful server response' do
            before do
              stub_request(method, uri).to_return body: resource_message.encode
            end

            it 'returns true' do
              assert @resource.save, 'save was not successful'
            end

            it 'saves the resource and parses the server response' do
              @resource.ordered_tests = 'no'
              @resource.save

              assert_requested method, uri,
                times: 1, body: ResourceMessage.new(id: id, ordered_tests: 'no', nested_int: {value: 100}).encode
              assert_equal 'yes', @resource.ordered_tests
            end
          end

          describe 'with a 422 server response' do
            before do
              stub_request(method, uri)
                .to_return body: errors_message.encode, status: 422
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
  end
end