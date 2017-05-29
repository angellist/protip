require 'test_helper'

require 'protip/decorator'
require 'protip/transformers/default_transformer'

require 'google/protobuf'
require 'google/protobuf/wrappers_pb'

require 'protip/messages/test_pb' # For the enum hack

# Tests the whole decoration/transformation process with the default
# transformer, using well-known types and other transformable message
# types.
describe Protip::Decorator do
  let(:decorated_message) { raise NotImplementedError }
  let(:transformer) { Protip::Transformers::DefaultTransformer.new }
  let(:decorator) { Protip::Decorator.new decorated_message, transformer }

  let(:pool) do
    pool = ::Google::Protobuf::DescriptorPool.new
    pool.build do
      add_enum 'number' do
        value :ZERO, 0
        value :ONE, 1
        value :TWO, 2
      end
      add_message 'inner_message' do
        optional :value, :int64, 1
        optional :note, :string, 2
      end
      add_message 'google.protobuf.StringValue' do
        optional :value, :string, 1
      end
      add_message 'protip.messages.EnumValue' do
        optional :value, :int32, 1
      end
      add_message 'message' do
        optional :inner, :message, 1, 'inner_message'
        optional :string_value, :message, 2, 'google.protobuf.StringValue'
        optional :enum_value, :message, 3, 'protip.messages.EnumValue'
        optional :string, :string, 4

        optional :inner_alternate, :message, 5, 'inner_message'
      end
    end
    pool
  end
  let(:message_class) { pool.lookup('message').msgclass }
  let(:inner_message_class) { pool.lookup('inner_message').msgclass }
  let(:string_value_class) { pool.lookup('google.protobuf.StringValue').msgclass }
  let(:enum_value_class) { pool.lookup('protip.messages.EnumValue').msgclass }

  describe 'getters' do
    # Temporary while our hacky enum detection is still necessary
    before do
      Protip::Transformers::EnumTransformer.stubs(:enum_for_field).
        with(message_class.descriptor.lookup('enum_value')).
        returns(pool.lookup('number'))
    end

    let(:decorated_message) do
      message_class.new(
        inner: inner_message_class.new(value: 50),
        string_value: string_value_class.new(value: 'salt'),
        enum_value: enum_value_class.new(value: 1),
        string: 'peppa',
      )
    end
    it 'returns a decorated version of the inner message' do
      result = decorator.inner
      assert_instance_of Protip::Decorator, result
      assert_equal 50, result.value
    end
    it 'returns nil for nil messages' do
      assert_nil decorator.inner_alternate
    end
    it 'returns a string for the StringValue message' do
      assert_equal 'salt', decorator.string_value
    end
    it 'returns a symbol for the EnumValue message' do
      assert_equal :ONE, decorator.enum_value
    end
    it 'returns an integer for the EnumValue message if the value is out of range' do
      decorated_message.enum_value.value = 4
      assert_equal 4, decorator.enum_value
    end
    it 'returns primitives directly' do
      assert_equal 'peppa', decorator.string
    end
  end

  describe 'setters' do
    # Temporary while our hacky enum detection is still necessary
    before do
      Protip::Transformers::EnumTransformer.stubs(:enum_for_field).
        with(message_class.descriptor.lookup('enum_value')).
        returns(pool.lookup('number'))
    end

    let(:decorated_message) do
      message_class.new
    end

    it 'allows setting the inner message directly' do
      inner_message = inner_message_class.new(value: 70)
      decorator.inner = inner_message
      assert_equal inner_message, decorated_message.inner
    end
    it 'allows setting the inner message from another decorator' do
      inner_message = inner_message_class.new(value: 80)
      decorator.inner = Protip::Decorator.new(inner_message, transformer)
      assert_equal inner_message, decorated_message.inner
    end
    it 'allows setting the inner message by hash' do
      decorator.inner = {value: 90}
      assert_equal inner_message_class.new(value: 90),
        decorated_message.inner
    end

    it 'allows setting the StringValue by message' do
      string_value_message = string_value_class.new(value: 'Tool')
      decorator.string_value = string_value_message
      assert_equal string_value_message, decorated_message.string_value
    end
    it 'allows setting the StringValue by string' do
      decorator.string_value = 'TMV'
      assert_equal string_value_class.new(value: 'TMV'), decorated_message.string_value
    end

    it 'allows setting the EnumValue by symbol' do
      decorator.enum_value = :ONE
      assert_equal enum_value_class.new(value: 1), decorated_message.enum_value
    end
    it 'allows setting the EnumValue by string' do
      decorator.enum_value = 'TWO'
      assert_equal enum_value_class.new(value: 2), decorated_message.enum_value
    end
    it 'allows setting the EnumValue by number' do
      decorator.enum_value = 4
      assert_equal enum_value_class.new(value: 4), decorated_message.enum_value
    end
    it 'raises an error when setting the EnumValue by an undefined symbol' do
      assert_raises RangeError do
        decorator.enum_value = :BLUE
      end
    end

    it 'allows setting primitive fields directly' do
      decorator.string = 'hai'
      assert_equal 'hai', decorated_message.string
    end

    it 'allows nulling message fields' do
      decorator.string_value = nil
      decorator.enum_value = nil
      decorator.inner = nil

      assert_nil decorated_message.string_value
      assert_nil decorated_message.enum_value
      assert_nil decorated_message.inner
    end
  end

  describe 'enum hacks' do # Temp - test an actual compiled file to make sure our options hack is working
    let(:decorated_message) { Protip::Messages::EnumTest.new }
    let(:decorator) { Protip::Decorator.new decorated_message, transformer }

    let(:value_map) do
      {
        :ONE => :ONE,
        1 => :ONE,
        2 => 2,
      }
    end

    it 'allows setting and getting a scalar field by Ruby value' do
      value_map.each do |value, expected|
        decorator.enum = value
        assert_equal expected, decorator.enum
      end
      assert_raises RangeError do
        decorator.enum = :TWO
      end
    end
    it 'allows setting and getting a scalar field by message' do
      decorator.enum = Protip::Messages::EnumValue.new(value: 1)
      assert_equal :ONE, decorator.enum
    end

    it 'allows setting and getting a repeated field by Ruby value' do
      value_map.each do |value, expected|
        decorator.repeated_enums = [value]
        assert_equal [expected], decorator.repeated_enums
      end
      assert_raises RangeError do
        decorator.repeated_enums = [:TWO]
      end
    end
    it 'allows setting and geting a repeated field by message' do
      decorator.repeated_enums = Protip::Messages::RepeatedEnum.new(values: [2])
      assert_equal [2], decorator.repeated_enums
    end
  end
end
