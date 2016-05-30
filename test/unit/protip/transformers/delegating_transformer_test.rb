require 'test_helper'
require 'protip/transformers/delegating_transformer'

require 'google/protobuf'

describe Protip::Transformers::DelegatingTransformer do
  let(:pool) do
    pool = ::Google::Protobuf::DescriptorPool.new
    pool.build do
      # We just need a couple empty message types
      add_message('message_one') { }
      add_message('message_two') { }
    end
    pool
  end
  %w(one two).each do |name|
    let(:"message_#{name}_class") do
      pool.lookup("message_#{name}").msgclass
    end
  end
  %i(one two fallback).each do |name|
    let(:"transformer_#{name}") do
      mock("transformer_#{name}").
        responds_like_instance_of(Class.new { include Protip::Transformer })
    end

    let(:"field_#{name}") do
      field = mock("field_#{name}").
        responds_like_instance_of(::Google::Protobuf::FieldDescriptor)
      field.stubs(:submsg_name).returns("message_#{name}")
      field
    end
  end
  let(:delegating_transformer) do
    transformer = Protip::Transformers::DelegatingTransformer.new(transformer_fallback)
    transformer['message_one'] = transformer_one
    transformer['message_two'] = transformer_two
    transformer
  end

  describe '#to_object' do
    let(:transformed_message) { mock 'transformed message' }
    let(:result) { mock 'result' }
    it 'delegates to transformers based on the message type being transformed' do
      transformer_one.expects(:to_object).
        once.
        with(transformed_message, field_one).
        returns(result)

      assert_equal result, delegating_transformer.to_object(transformed_message, field_one)
    end

    it 'delegates to the fallback transformer when the message type has not been configured' do
      transformer_fallback.expects(:to_object).
        once.
        with(transformed_message, field_fallback).
        returns(result)
      assert_equal result,
        delegating_transformer.to_object(transformed_message, field_fallback)
    end
  end

  describe '#to_message' do
    let(:result) { mock 'result' }
    let(:object) { mock 'object' }
    it 'delegates to transformers based on the message type being transformed' do
      transformer_two.expects(:to_message).
        once.
        with(object, field_two).
        returns(result)
      assert_equal result, delegating_transformer.to_message(object, field_two)
    end

    it 'delegates to the fallback transformer when the message type has not been configured' do
      transformer_fallback.expects(:to_message).
        once.
        with(object, field_fallback).
        returns(result)
      assert_equal result,
        delegating_transformer.to_message(object, field_fallback)
    end
  end
end
