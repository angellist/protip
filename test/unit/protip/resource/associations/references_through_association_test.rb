require 'test_helper'

require 'protip/resource/associations/references_through_association'

describe Protip::Resource::Associations::ReferencesThroughAssociation do
  let :pool do
    pool = Google::Protobuf::DescriptorPool.new
    pool.build do
      # Allow nil ID fields
      add_message 'google.protobuf.StringValue' do
        optional :value, :string, 1
      end
      add_message 'ResourceMessage' do
        optional :id, :message, 1, 'google.protobuf.StringValue'
        optional :referenced_resource_id, :message, 2, 'google.protobuf.StringValue'
      end
      add_message 'ReferenceMessage' do
        optional :id, :message, 1, 'google.protobuf.StringValue'
      end
    end
    pool
  end
  let :resource_class do
    klass = Class.new do
      include Protip::Resource
    end
    klass.class_exec(pool) do |pool|
      resource actions: [], message: pool.lookup('ResourceMessage').msgclass
    end
    klass
  end

  let :referenced_resource_class do
    klass = Class.new do
      include Protip::Resource
    end
    klass.class_exec(pool) do |pool|
      resource actions: [], message: pool.lookup('ReferenceMessage').msgclass
    end
    klass
  end

  describe '#initialize' do
    it 'chooses a default class based on the ID field' do
      Object.stub_const 'ReferencedResource', referenced_resource_class do
        reference = Protip::Resource::Associations::ReferencesThroughAssociation.new resource_class,
          :referenced_resource_id
        assert_equal referenced_resource_class, reference.reference_class
      end
    end
    it 'allows a class name to be set' do
      Object.stub_const 'Foo', referenced_resource_class do
        reference = Protip::Resource::Associations::ReferencesThroughAssociation.new resource_class,
          :referenced_resource_id, class_name: 'Foo'
        assert_equal referenced_resource_class, reference.reference_class
      end
    end
    it 'chooses a default association name based on the ID field' do
      Object.stub_const 'ReferencedResource', referenced_resource_class do
        reference = Protip::Resource::Associations::ReferencesThroughAssociation.new resource_class,
          :referenced_resource_id
        assert_equal :referenced_resource, reference.reference_name
      end
    end
    it 'allows an association name to be set' do
      Object.stub_const 'ReferencedResource', referenced_resource_class do
        reference = Protip::Resource::Associations::ReferencesThroughAssociation.new resource_class,
          :referenced_resource_id, reference_name: :foo
        assert_equal :foo, reference.reference_name
      end
    end
  end

  describe '(accessors)' do
    let :reference do
      reference = Protip::Resource::Associations::ReferencesThroughAssociation.new resource_class,
        :referenced_resource_id
      reference.stubs(:reference_class).returns(referenced_resource_class)
      reference
    end

    let :resource do
      resource_class.new
    end

    describe '#read' do
      it 'finds the association by ID' do
        referenced_resource = mock
        referenced_resource_class.expects(:find).once.with('asdf').returns(referenced_resource)
        resource.referenced_resource_id = 'asdf'
        assert_equal referenced_resource, reference.read(resource)
      end

      it 'returns nil if the resource has not been set' do
        resource.referenced_resource_id = nil
        referenced_resource_class.expects(:find).never
        assert_nil reference.read(resource)
      end
    end

    describe '#write' do
      it 'raises an error if given the wrong resource type' do
        assert_raises ArgumentError do
          reference.write(resource, resource)
        end
      end

      it 'raises an error if given a non-persisted resource' do
        assert_raises RuntimeError do
          reference.write(resource, referenced_resource_class.new)
        end
      end

      it 'assigns nil if nil is given' do
        resource.referenced_resource_id = 'asdf'
        reference.write(resource, nil)
        assert_nil resource.referenced_resource_id
      end

      it 'assigns the resource ID if a persisted resource of the correct type is given' do
        reference.write(resource, referenced_resource_class.new(id: 'foo'))
        assert_equal 'foo', resource.referenced_resource_id
      end
    end
  end

end
