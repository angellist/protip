require 'test_helper'
require 'protip/transformers/timestamp_transformer'
require 'google/protobuf/timestamp'

describe Protip::Transformers::TimestampTransformer do
  let(:transformer) { Protip::Transformers::TimestampTransformer.new }
  let(:field) do
    field = mock.responds_like_instance_of Google::Protobuf::FieldDescriptor
    descriptor = Google::Protobuf::Timestamp.descriptor
    field.stubs(:submsg_name).returns(descriptor.name)
    field.stubs(:subtype).returns(descriptor)
    field
  end

  describe '#to_object' do
    it 'creates a timestamp' do
      message = Google::Protobuf::Timestamp.new(seconds: 1415, nanos: 12345678)
      result = transformer.to_object(message, field)
      assert_instance_of ::Time, result
      assert_equal 1415, result.to_i
      assert_equal 12345678, result.nsec
    end
  end

  describe '#to_message' do
    let(:timestamp) do
      ::Time.at(601, 1)
    end
    let(:expected_message) do
      Google::Protobuf::Timestamp.new(
        seconds: 601,
        nanos: 1000,
      )
    end
    it 'converts times directly' do
      assert_equal expected_message,
        transformer.to_message(timestamp, field)
    end
    it 'converts non-times via :to_time' do
      object = mock 'object'
      object.expects(:to_time).once.returns(timestamp)
      assert_equal expected_message,
        transformer.to_message(object, field)
    end
  end
end
