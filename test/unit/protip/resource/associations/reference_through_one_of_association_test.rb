require 'test_helper'

require 'protip/resource/associations/references_through_one_of_association'

describe 'Protip::Resource::Associations::ReferencesThroughOneOfAssociation' do

  let :resource_class do
    pool = Google::Protobuf::DescriptorPool.new
    pool.build do
      add_message 'ResourceMessage' do
        optional :id, :string, 1
        oneof :reference_id do
          optional :rick_ross_id, :string, 2
          optional :fetty_wap_id, :string, 3
        end
      end
    end
    Class.new do
      include Protip::Resource
      resource actions: [], message: pool.lookup('ResourceMessage').msgclass
    end
  end


  describe '#initialize' do
    it 'creates ReferencesThroughAssociation\'s for all nested fields' do
      klass = Protip::Resource::Associations::ReferencesThroughAssociation
      id_fields = [:rick_ross_id, :fetty_wap_id]
      klass.expects(:new).twice.with do |klass, id_field, options|
        result = klass == resource_class && id_fields.include?(id_field) && options == {}
        id_fields.delete(id_field)
        result
      end.returns(mock.responds_like_instance_of(klass), mock.responds_like_instance_of(klass))
      Protip::Resource::Associations::ReferencesThroughOneOfAssociation.new resource_class, :reference_id
    end

    it 'forwards individual field options to the created ReferencesThroughAssociation' do
      klass = Protip::Resource::Associations::ReferencesThroughAssociation
      klass.expects(:new).twice.with do |klass, id_field, options|
        if klass == resource_class
          if id_field == :rick_ross_id
            options == {class_name: 'Foo'}
          else
            options == {class_name: 'Bar'}
          end
        else
          false
        end
      end

      Protip::Resource::Associations::ReferencesThroughOneOfAssociation.new resource_class, :reference_id,
        field_options: {
          rick_ross_id: {class_name: 'Foo'},
          'fetty_wap_id' => {class_name: 'Bar'} # Try a string key as well
        }
    end
  end

  describe '(accessors)' do
    ## Shared initialization for #read and #write

    # Mock the actual references-through associations that are generated for sub-fields
    let(:rick_ross_reference) do
      mock.responds_like_instance_of Protip::Resource::Associations::ReferencesThroughAssociation
    end
    let(:fetty_wap_reference) do
      mock.responds_like_instance_of Protip::Resource::Associations::ReferencesThroughAssociation
    end

    # And set up the references-through constructor to return the correct mocks
    before do
      count = 0
      Protip::Resource::Associations::ReferencesThroughAssociation.expects(:new).with do |resource_class, id_field|
        count += 1
        if count == 1 # Sanity check, make sure the mock references are assigned in the correct order
          id_field == :rick_ross_id
        elsif count == 2
          id_field == :fetty_wap_id
        else
          raise 'unexpected'
        end
      end.at_most(2).returns(rick_ross_reference, fetty_wap_reference)
    end

    # The actual references-through-one-of object for the oneof field
    let(:reference) do
      Protip::Resource::Associations::ReferencesThroughOneOfAssociation.new resource_class, :reference_id
    end

    describe '#read' do
      it 'forwards to the nested association that\'s currently been set' do
        # Create a test instance with one of the fields set
        resource = resource_class.new fetty_wap_id: 'test'

        rick_ross_reference.expects(:read).never
        fetty_wap_reference.expects(:read).once.with(resource).returns('come my way')

        assert_equal 'come my way', reference.read(resource)
      end

      it 'returns nil if no nested association has been set' do
        resource = resource_class.new

        rick_ross_reference.expects(:read).never
        fetty_wap_reference.expects(:read).never

        assert_nil reference.read(resource)
      end
    end

    describe '#write' do
      let(:rick_ross_class) { Class.new }
      let(:fetty_wap_class) { Class.new }
      before do
        rick_ross_reference.stubs(:reference_class).returns(rick_ross_class)
        fetty_wap_reference.stubs(:reference_class).returns(fetty_wap_class)
      end
      it 'forwards to the nested association that matches the class being set' do
        resource = resource_class.new
        fetty_wap = fetty_wap_class.new

        rick_ross_reference.expects(:write).never
        fetty_wap_reference.expects(:write).once.with(resource, fetty_wap)

        reference.write(resource, fetty_wap)
      end

      # Sanity check, try out forwarding for the other type as well
      it 'forwards to the nested association that matches the class being set, if that association comes first' do
        resource = resource_class.new
        rick_ross = rick_ross_class.new

        rick_ross_reference.expects(:write).once.with(resource, rick_ross)
        fetty_wap_reference.expects(:write).never

        reference.write(resource, rick_ross)
      end

      it 'wipes all associations if nil is given' do
        resource = resource_class.new
        resource.rick_ross_id = 'asfd'

        reference.write(resource, nil)

        assert_nil resource.rick_ross_id
        assert_nil resource.fetty_wap_id
      end
    end

    describe '#define_accessors!' do
      it 'forwards to all nested associations' do
        rick_ross_reference.expects(:define_accessors!).once
        fetty_wap_reference.expects(:define_accessors!).once

        reference.define_accessors!
      end

      it 'defines accessors for the oneof association' do
        rick_ross_reference.stubs(:define_accessors!)
        fetty_wap_reference.stubs(:define_accessors!)

        reference.define_accessors!

        resource = resource_class.new
        assert_respond_to resource, :reference
        assert_respond_to resource, :reference=
      end
    end

  end
end