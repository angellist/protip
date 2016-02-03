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
      klass.expects(:new).with(resource_class, :rick_ross_id).returns(mock.responds_like_instance_of klass).then
        .expects(:new).with(resource_class, :fetty_wap_id).returns(mock.responds_like_instance_of klass).then
        .expects(:new).never
      Protip::Resource::Associations::ReferencesThroughOneOfAssociation.new resource_class, :reference_id
    end

    it 'forwards individual field options to the created ReferencesThroughAssociation' do

    end
  end

  describe '#read' do

  end
end