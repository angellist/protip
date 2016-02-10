require 'test_helper'

require 'protip/resource/associations/belongs_to_polymorphic_association'

describe Protip::Resource::Associations::BelongsToPolymorphicAssociation do

  let :resource_class do
    pool = Google::Protobuf::DescriptorPool.new
    pool.build do
      add_message 'ResourceMessage' do
        optional :id, :string, 1
        oneof :reference_id do
          optional :rick_ross_id, :string, 2
          optional :fetty_wap_id, :string, 3
        end
        optional :other_id, :string, 4
      end
    end
    Class.new do
      include Protip::Resource
      resource actions: [], message: pool.lookup('ResourceMessage').msgclass
    end
  end

  let :rick_ross_association do
    association = mock.responds_like_instance_of(Protip::Resource::Associations::BelongsToAssociation)
    association.stubs(:id_field).returns(:rick_ross_id)
    association
  end

  let :fetty_wap_association do
    association = mock.responds_like_instance_of(Protip::Resource::Associations::BelongsToAssociation)
    association.stubs(:id_field).returns(:fetty_wap_id)
    association
  end

  let :other_association do
    association = mock.responds_like_instance_of(Protip::Resource::Associations::BelongsToAssociation)
    association.stubs(:id_field).returns(:other_id)
    association
  end

  describe '#initialize' do
    it 'raises an error unless a belongs-to association is provided for all nested fields' do
      error = assert_raises ArgumentError do
        Protip::Resource::Associations::BelongsToPolymorphicAssociation.new resource_class,
          :reference, [rick_ross_association]
      end
      assert_match /requires an association to be defined/, error.message
    end

    it 'raises an error if a belongs-to association is provided for a field outside the oneof' do
      error = assert_raises ArgumentError do
        Protip::Resource::Associations::BelongsToPolymorphicAssociation.new resource_class,
          :reference, [rick_ross_association, other_association]
      end
      assert_match /requires an association to be defined/, error.message
    end

    it 'raises an error if a duplicate belongs-to association is provided' do
      error = assert_raises ArgumentError do
        Protip::Resource::Associations::BelongsToPolymorphicAssociation.new resource_class,
          :reference, [rick_ross_association, rick_ross_association, fetty_wap_association]
      end
      assert_match /Duplicate association/, error.message
    end

    it 'allows the oneof ID field to be specified' do
     association = Protip::Resource::Associations::BelongsToPolymorphicAssociation.new resource_class,
       :foo, [rick_ross_association, fetty_wap_association], id_field: :reference_id
      assert_equal :reference_id, association.id_field
    end

    it 'stores the nested belongs-to associations' do
      association = Protip::Resource::Associations::BelongsToPolymorphicAssociation.new resource_class,
        :reference, [rick_ross_association, fetty_wap_association]
      assert_equal 2, association.belongs_to_associations.length
      assert_includes association.belongs_to_associations, rick_ross_association
      assert_includes association.belongs_to_associations, fetty_wap_association
    end
  end

  describe '(accessors)' do
    let(:association) do
      Protip::Resource::Associations::BelongsToPolymorphicAssociation.new resource_class, :reference,
        [rick_ross_association, fetty_wap_association]
    end

    describe '#read' do
      it 'forwards to the nested association that\'s currently been set' do
        # Create a test instance with one of the fields set
        resource = resource_class.new fetty_wap_id: 'test'

        rick_ross_association.expects(:read).never
        fetty_wap_association.expects(:read).once.with(resource).returns('come my way')

        assert_equal 'come my way', association.read(resource)
      end

      it 'returns nil if no nested association has been set' do
        resource = resource_class.new

        rick_ross_association.expects(:read).never
        fetty_wap_association.expects(:read).never

        assert_nil association.read(resource)
      end
    end

    describe '#write' do
      let(:rick_ross_class) { Class.new }
      let(:fetty_wap_class) { Class.new }
      before do
        rick_ross_association.stubs(:associated_resource_class).returns(rick_ross_class)
        fetty_wap_association.stubs(:associated_resource_class).returns(fetty_wap_class)
      end
      it 'forwards to the nested association that matches the class being set' do
        resource = resource_class.new
        fetty_wap = fetty_wap_class.new

        rick_ross_association.expects(:write).never
        fetty_wap_association.expects(:write).once.with(resource, fetty_wap)

        association.write(resource, fetty_wap)
      end

      # Sanity check, try out forwarding for the other type as well
      it 'forwards to the nested association that matches the class being set, if that association comes first' do
        resource = resource_class.new
        rick_ross = rick_ross_class.new

        rick_ross_association.expects(:write).once.with(resource, rick_ross)
        fetty_wap_association.expects(:write).never

        association.write(resource, rick_ross)
      end

      it 'wipes all associations if nil is given' do
        resource = resource_class.new
        resource.rick_ross_id = 'asfd'

        association.write(resource, nil)

        assert_nil resource.rick_ross_id
        assert_nil resource.fetty_wap_id
      end
    end
  end
end