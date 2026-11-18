require 'test_helper'
require 'google/protobuf/wrappers_pb'

describe 'Protip member paths' do
  let :resource_class do
    Class.new do
      include Protip::Resource

      resource actions: [:show, :create, :update, :destroy],
        message: Google::Protobuf::StringValue
      member action: :archive, method: :post

      self.base_path = 'resources'
      self.client = Class.new do
        include Protip::Client
      end.new
      client.base_uri = 'https://external.service'

      def id
        value
      end
    end
  end

  [
    ['../../x.json?ids=1', '..%2F..%2Fx.json%3Fids%3D1'],
    ['id?ids=1', 'id%3Fids%3D1'],
    ['id#fragment', 'id%23fragment'],
    ['%2e%2e', '%252e%252e'],
    ['id\\other', 'id%5Cother'],
    ['id with space', 'id%20with%20space'],
    ['01234567-89ab-4cde-8fab-0123456789ab', '01234567-89ab-4cde-8fab-0123456789ab'],
    [123, '123'],
    [0, '0'],
  ].each do |id, segment|
    [:find, :save, :destroy, :archive].each do |action|
      it "encodes #{id.inspect} as one segment through #{action}" do
        resource = resource_class.new(value: id.to_s)
        path = "https://external.service/resources/#{segment}"
        path += '/archive' if action == :archive
        method = {find: :get, save: :put, destroy: :delete, archive: :post}.fetch(action)
        request = stub_request(method, path).
          to_return(body: resource.message.class.encode(resource.message))

        if action == :find
          resource_class.find(id)
        else
          resource.public_send(action)
        end

        assert_requested request, times: 1
      end
    end
  end

  [nil, '', '.', '..'].each do |id|
    [:find, :save, :destroy, :archive].each do |action|
      next if id.nil? && action == :save

      it "rejects #{id.inspect} before a request through #{action}" do
        resource = resource_class.new
        resource.define_singleton_method(:id) { id }
        request = stub_request(:any, /https:\/\/external.service/)

        error_class = id.nil? && action == :destroy ? RuntimeError : ArgumentError
        error = assert_raises(error_class) do
          action == :find ? resource_class.find(id) : resource.public_send(action)
        end
        assert_equal "Can't destroy a non-persisted object", error.message if id.nil? && action == :destroy
        assert_not_requested request
      end
    end
  end

  it 'rejects a nil ID in the shared member path helper' do
    assert_raises(ArgumentError) { Protip::Resource::MemberPath.build(resource_class, nil) }
  end

  it 'keeps save with a nil ID on the collection create path' do
    resource = resource_class.new
    resource.define_singleton_method(:id) { nil }
    request = stub_request(:post, 'https://external.service/resources').
      to_return(body: resource.message.class.encode(resource.message))

    assert resource.save
    assert_requested request, times: 1
  end
end
