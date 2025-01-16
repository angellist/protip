require 'test_helper'
require 'base64'

require 'protip/transformers/primitives_transformer'

require 'google/protobuf/wrappers_pb'
require 'protip/messages/errors_pb'

describe ::Protip::Transformers::PrimitivesTransformer do
  let(:transformer) { ::Protip::Transformers::PrimitivesTransformer.new }
  let(:message_class) { raise NotImplementedError } # sub-sections must define
  let(:field) do
    field = mock.responds_like_instance_of ::Google::Protobuf::FieldDescriptor
    field.stubs(:submsg_name).returns(message_class.descriptor.name)
    field.stubs(:subtype).returns(message_class.descriptor)
    field
  end

  INTEGER_TYPES = %w(Int64 Int32 UInt64 UInt32)
  FLOAT_TYPES = %w(Float Double)
  STRING_TYPES = %w(String)
  BOOLEAN_TYPES = %w(Bool)
  BYTES_TYPES = %w(Bytes)

  BYTES_VALUE = Base64.decode64("U2VuZCByZWluZm9yY2VtZW50cw==\n")

  {
    6           => INTEGER_TYPES,
    5.5         => FLOAT_TYPES,
    'foo'       => STRING_TYPES,
    true        => BOOLEAN_TYPES,
    BYTES_VALUE => BYTES_TYPES,
  }.each do |value, types|
     types.each do |type|
       describe '#to_object' do
        describe "google.protobuf.#{type}Value" do
          let(:message_class) { Google::Protobuf.const_get("#{type}Value") }
          it 'converts scalar messages' do
            assert_equal value, transformer.to_object(message_class.new(value: value), field)
          end
        end

        describe "protip.messages.Repeated#{type}" do
          let(:message_class) { Protip::Messages.const_get("Repeated#{type}") }
          it 'converts repeated mesages to an immutable array' do
            result = transformer.to_object(message_class.new(values: [value, value]), field)
            assert_equal [value, value], result

            exception = assert_raises RuntimeError do
              result << value
            end
            assert_match 'can\'t modify frozen Array', exception.message
          end
        end

        describe '#to_message' do
          # Keys are the actual value that should be set on the message,
          # values are an object of a different type that should be converted.
          # Used for testing that e.g. integer types can be set using numeric strings.
          if INTEGER_TYPES.include?(type) || FLOAT_TYPES.include?(type)
            let(:native_to_non_native) { {value => value.to_s} }
          elsif STRING_TYPES.include?(type)
            let(:native_to_non_native) { {'3' => 3} }
          elsif BOOLEAN_TYPES.include?(type)
            let(:native_to_non_native) { {true => 'on', false => 'off'} }
          else
            let(:native_to_non_native) { {} }
          end

          describe "google.protobuf.#{type}Value" do
            let(:message_class) { Google::Protobuf.const_get("#{type}Value") }
            it 'converts scalar types to a message' do
              assert_equal message_class.new(value: value), transformer.to_message(value, field)
            end

            it "converts non-#{type} types to a #{type} message" do
              native_to_non_native.each do |native, non_native|
                assert_equal message_class.new(value: native),
                  transformer.to_message(non_native, field)
              end
            end
          end

          describe "protip.messages.Repeated#{type}" do
            let(:message_class) { Protip::Messages.const_get("Repeated#{type}") }

            it 'converts repeated types when given a scalar' do
              assert_equal message_class.new(values: [value]),
                transformer.to_message(value, field)
            end

            it 'converts repeated types when given an array' do
              assert_equal message_class.new(values: [value, value]),
                transformer.to_message([value, value], field)
            end

            it "converts non-#{type} scalar types to a repeated #{type} message" do
              native_to_non_native.each do |native, non_native|
                assert_equal message_class.new(values: [native]),
                  transformer.to_message(non_native, field)
              end
            end

            it "converts non-#{type} array types to a repeated #{type} message" do
              native_to_non_native.each do |native, non_native|
                assert_equal message_class.new(values: [native, native]),
                  transformer.to_message([non_native, non_native], field)
              end
            end
          end
        end
      end
    end
  end

  describe '#to_message' do
    let(:message_class) { Google::Protobuf::BoolValue }
    it 'converts all truthy values to booleans' do
      [true, 1, '1', 't', 'T', 'true', 'TRUE', 'on', 'ON'].each do |truth_value|
        assert_equal Google::Protobuf::BoolValue.new(value: true),
          transformer.to_message(truth_value, field)
      end
    end
    it 'converts all falsey values to booleans' do
      [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF'].each do |false_value|
        assert_equal Google::Protobuf::BoolValue.new(value: false),
          transformer.to_message(false_value, field)
      end
    end

    it 'raises an exception if non-boolean values passed to a boolean field' do
      ['test', Object.new, 2, {}, []].each do |bad_value|
        assert_raises TypeError do
          transformer.to_message(bad_value, field)
        end
      end
    end
  end
end
