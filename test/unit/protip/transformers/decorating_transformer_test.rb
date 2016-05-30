require 'test_helper'
require 'protip/transformers/decorating_transformer'

require 'google/protobuf'

describe Protip::Transformers::DecoratingTransformer do
  let(:parent_transformer) do
    mock('parent transformer')
  end
  let(:transformer) do
    Protip::Transformers::DecoratingTransformer.new(parent_transformer)
  end
  describe '#to_object' do
    let(:field) { mock 'field' }
    let(:from_message) { mock 'message' }
    let(:object) { transformer.to_object(from_message, field) }
    it 'returns a decorator' do
      assert_instance_of Protip::Decorator, object
    end
    it 'passes along the message' do
      assert_equal from_message, object.message
    end
    it 'passes along the transformer' do
      assert_equal parent_transformer, object.transformer
    end
  end

  describe '#to_message' do
    let(:pool) do
      pool = Google::Protobuf::DescriptorPool.new
      pool.build do
        add_message 'message' do
          optional :value, :int64, 1
        end
      end
      pool
    end
    let(:message_class) { pool.lookup('message').msgclass }
    let(:field) do
      field = mock.responds_like_instance_of ::Google::Protobuf::FieldDescriptor
      field.stubs(:submsg_name).returns(message_class.descriptor.name)
      field.stubs(:subtype).returns(message_class.descriptor)
      field
    end

    describe 'when given a decorator' do
      let(:decorated_message) do
        mock('message')
      end
      let(:decorator) do
        Protip::Decorator.new(decorated_message, mock('transformer'))
      end
      it 'returns the decorated message' do
        assert_equal decorated_message, transformer.to_message(decorator, field)
      end
    end

    describe 'when given a hash' do
      it 'assigns the hash attributes through a decorator' do
        created_message = mock('created message')
        created_decorator =
          mock('created decorator').responds_like_instance_of(Protip::Decorator)
        Protip::Decorator.expects(:new).
          once.
          # We expect a newly-generated message, and the transformer
          # that we use for our decorators.
          with(message_class.new, parent_transformer).
          returns(created_decorator)

        assignment = sequence 'assignment'
        created_decorator.expects(:assign_attributes).
          once.
          in_sequence(assignment).
          with(value: 55)
        created_decorator.expects(:message).
          once.
          in_sequence(assignment).
          returns(created_message)

        assert_equal created_message, transformer.to_message({value: 55}, field)
      end

      # Simple functional test without all the complex transformer
      # mocks - transformer never touched because the message only has
      # a primitive field.
      it 'assigns the hash attributes (functional)' do
        message = transformer.to_message({value: 12}, field)
        assert_equal message_class.new(value: 12), message
      end
    end
  end
end
