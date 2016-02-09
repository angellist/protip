require 'test_helper'

require 'google/protobuf'
require 'protip/resource/associations/association'

describe Protip::Resource::Associations::Association do
  let :resource_class do
    pool = Google::Protobuf::DescriptorPool.new
    pool.build do
      add_message 'ResourceMessage' do
        optional :id, :string, 1
      end
    end
    Class.new do
      include Protip::Resource
      resource actions: [], message: pool.lookup('ResourceMessage').msgclass
    end
  end

  let :association_class do
    Class.new do
      include Protip::Resource::Associations::Association
      attr_reader :resource_class, :association_name
      def initialize(resource_class, association_name)
        @resource_class, @association_name = resource_class, association_name
      end
    end
  end

  describe '#define_accessors!' do
    let :association do
      association_class.new(resource_class, :reference)
    end

    it 'defines read and write methods' do
      # Sanity checks
      refute_includes resource_class.instance_methods, :reference, 'reader already set'
      refute_includes resource_class.instance_methods, :reference=, 'writer already set'

      association.define_accessors!

      assert_includes resource_class.instance_methods, :reference, 'reader not set'
      assert_includes resource_class.instance_methods, :reference=, 'writer not set'
    end

    describe '(after invoked)' do
      let :resource do
        resource_class.new
      end

      before do
        association.define_accessors!
      end

      it 'receives reader calls from resource instances' do
        association.expects(:read).once.with(resource)
        resource.reference
      end

      it 'receives writer calls from resource instances' do
        association.expects(:write).once.with(resource, 'test')
        resource.reference = 'test'
      end
    end
  end
end