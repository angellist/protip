require 'test_helper'

require 'google/protobuf'

require 'protip/decorator'
require 'protip/resource'
require 'protip/transformer'

module Protip::DecoratorTest # namespace for internal constants
  describe Protip::Decorator do
    let(:transformer) do
      Class.new do
        include Protip::Transformer
      end.new
    end

    let(:pool) do
      pool = Google::Protobuf::DescriptorPool.new
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
        add_message 'google.protobuf.BoolValue' do
          optional :value, :bool, 1
        end
        add_message 'protip.messages.EnumValue' do
          optional :value, :int32, 1
        end

        add_message 'message' do
          optional :inner, :message, 1, 'inner_message'
          optional :string, :string, 2

          repeated :inners, :message, 3, 'inner_message'
          repeated :strings, :string, 4

          optional :inner_blank, :message, 5, 'inner_message'

          optional :number, :enum, 6, 'number'
          repeated :numbers, :enum, 7, 'number'
          optional :number_message, :message, 8, 'protip.messages.EnumValue'

          optional :boolean, :bool, 9
          repeated :booleans, :bool, 10

          optional :google_bool_value, :message, 11, 'google.protobuf.BoolValue'
          repeated :google_bool_values, :message, 12, 'google.protobuf.BoolValue'

          oneof :oneof_group do
            optional :oneof_string1, :string, 13
            optional :oneof_string2, :string, 14
          end
        end
      end
      pool
    end

    %w(inner_message message).each do |name|
      let(:"#{name}_class") do
        pool.lookup(name).msgclass
      end
    end
    let(:enum_message_class) do
      pool.lookup('protip.messages.EnumValue').msgclass
    end
    let (:inner_message_field) { message_class.descriptor.lookup('inner') }

    # Stubbed API client
    let :client do
      mock.responds_like_instance_of(Class.new { include Protip::Client })
    end

    # Call `resource_class` to get an empty resource type.
    let :resource_class do
      resource_class = Class.new do
        include Protip::Resource
        self.base_path = 'base_path'
        class << self
          attr_accessor :client
        end
      end
      resource_class.client = client
      resource_class
    end

    # An actual protobuf message, which is used when building the decorator below
    let(:decorated_message) do
      message_class.new(inner: inner_message_class.new(value: 25), string: 'test')
    end

    let(:decorator) do
      Protip::Decorator.new(decorated_message, transformer)
    end

    # Stub the wrapped-enum fetcher method - probably rethink this once the
    # instance variable hack is no longer necessary
    before do
      Protip::Transformers::EnumTransformer.stubs(:enum_for_field)
        .returns(pool.lookup('number') || raise('unexpected - no enum field found'))
    end

    describe '#respond_to?' do
      it 'adds setters for message fields' do
        assert_respond_to decorator, :string=
        assert_respond_to decorator, :inner=
        assert_respond_to decorator, :inner_blank=
      end
      it 'adds getters for message fields' do
        assert_respond_to decorator, :string
        assert_respond_to decorator, :inner
        assert_respond_to decorator, :inner_blank
      end
      it 'adds accessors for oneof groups' do
        assert_respond_to decorator, :oneof_group
      end
      it 'adds queries for scalar fields' do
        assert_respond_to decorator, :number?, 'enum field should respond to query'
        assert_respond_to decorator, :number_message?, 'enum message field should respond to query'
        assert_respond_to decorator, :boolean?, 'bool field should respond to query'
        assert_respond_to decorator, :google_bool_value?, 'google.protobuf.BoolValue field should respond to query'
        assert_respond_to decorator, :inner?, 'non-bool message field should respond to query'
      end
      it 'adds queries for repeated fields' do
        assert_respond_to decorator, :numbers?, 'repeated enum field should respond to query'
        assert_respond_to decorator, :booleans?, 'repeated bool field should respond to query'
        assert_respond_to decorator, :google_bool_values?, 'repeated google.protobuf.BoolValue field should respond to query'
      end
      it 'responds to standard defined methods' do
        assert_respond_to decorator, :as_json
      end
      it 'does not add other setters/getters/queries' do
        refute_respond_to decorator, :foo=
        refute_respond_to decorator, :foo
        refute_respond_to decorator, :foo?
      end
      it 'does not add methods which partially match message fields' do
        refute_respond_to decorator, :xinner
        refute_respond_to decorator, :xinner=
        refute_respond_to decorator, :xnumber?
        refute_respond_to decorator, :innerx
        refute_respond_to decorator, :innerx=
        refute_respond_to decorator, :'inner=x'
        refute_respond_to decorator, :numberx?
        refute_respond_to decorator, :'number?x'
      end
    end

    describe '#build' do
      let(:decorated_message) { message_class.new }
      before do
        decorator.stubs(:get).returns(:opeth)
      end

      it 'raises an error when building a primitive field' do
        assert_raises RuntimeError do
          decorator.build(:string)
        end
      end

      it 'raises an error when building a repeated primitive field' do
        assert_raises RuntimeError do
          decorator.build(:strings)
        end
      end

      it 'builds the message when no attributes are provided' do
        assert_nil decorated_message.inner # Sanity check
        decorator.build(:inner)
        assert_equal inner_message_class.new, decorated_message.inner
      end

      it 'overwrites the message if it exists' do
        decorated_message.inner = inner_message_class.new(value: 4)
        decorator.build(:inner)
        assert_equal inner_message_class.new, decorated_message.inner
      end

      it 'delegates to #assign_attributes if attributes are provided' do
        # A decorator should be created with a new instance of the
        # message, and the same transformer as the main decorator.
        inner_decorator = mock('inner decorator')
        decorator.class.expects(:new).
          once.
          with(inner_message_class.new, transformer).
          returns(inner_decorator)

        # That decorator should be used to assign the given attributes
        assignment = sequence('assignment')
        inner_decorator.expects(:assign_attributes).
          in_sequence(assignment).
          once.
          with(value: 40)

        # And then return a message, which should be assigned to the
        # field being built (we return a mock with a different value
        # so we can check it in the next step).
        built_message = inner_message_class.new(value: 15)
        inner_decorator.expects(:message).
          in_sequence(assignment).
          once.
          returns(built_message)

        decorator.build(:inner, value: 40)
        assert_equal built_message, decorated_message.inner
      end

      it 'returns the built field' do
        built = decorator.build(:inner)
        assert_equal :opeth, built
      end
    end

    describe '#assign_attributes' do

      it 'assigns primitive fields directly' do
        decorator.assign_attributes string: 'another thing'
        assert_equal 'another thing', decorated_message.string
      end

      it 'assigns repeated primitive fields from an enumerator' do
        decorator.assign_attributes strings: ['one', 'two']
        assert_equal ['one', 'two'], decorated_message.strings
      end

      it 'assigns multiple attributes' do
        decorator.assign_attributes string: 'foo', strings: ['one', 'two']
        assert_equal 'foo', decorated_message.string
        assert_equal ['one', 'two'], decorated_message.strings
      end

      describe 'when assigning message fields with a non-hash' do

        it 'converts scalar Ruby values to protobuf messages' do
          transformer.expects(:to_message).
            once.
            with(45, inner_message_field).
            returns(inner_message_class.new(value: 43))

          decorator.assign_attributes inner: 45
          assert_equal inner_message_class.new(value: 43),
            decorated_message.inner
        end

        it 'converts repeated Ruby values to protobuf messages' do
          invocation = 0
          transformer.expects(:to_message).twice.with do |value|
            invocation += 1
            value == invocation
          end.returns(inner_message_class.new(value: 43), inner_message_class.new(value: 44))
          decorator.assign_attributes inners: [1, 2]
          assert_equal [inner_message_class.new(value: 43), inner_message_class.new(value: 44)],
            decorated_message.inners
        end

        it 'allows messages to be assigned directly' do
          message = inner_message_class.new
          decorator.assign_attributes inner: message
          assert_same message, decorated_message.inner
        end

        it "sets fields to nil when they're assigned nil" do
          decorated_message.inner = inner_message_class.new(value: 60)
          refute_nil decorated_message.inner
          decorator.assign_attributes inner: nil
          assert_nil decorated_message.inner
        end
      end

      it 'returns nil' do
        assert_nil decorator.assign_attributes({})
      end

      describe 'when assigning message fields with a hash' do
        it 'builds nil message fields and assigns attributes to them' do
          # We expect to transform an empty message, and then assign
          # attributes on it.
          transformed_inner_message = mock 'transfomred inner message'
          transformer.expects(:to_object).once.with(
            inner_message_class.new,
            instance_of(::Google::Protobuf::FieldDescriptor)
          ).returns(transformed_inner_message)
          transformed_inner_message.expects(:assign_attributes).
            once.
            with(note: 'created')

          decorated_message.inner = nil
          decorator.assign_attributes inner: {note: 'created'}
        end

        it 'updates message fields which are already present' do
          # We expect to transform the existing message, and then
          # assign attributes on it.
          transformed_inner_message = mock 'transformed inner message'
          inner_message = inner_message_class.new(value: 60)
          transformer.expects(:to_object).once.with(
            inner_message,
            instance_of(::Google::Protobuf::FieldDescriptor)
          ).returns(transformed_inner_message)

          transformed_inner_message.expects(:assign_attributes).
            once.
            with(note: 'updated')

          decorated_message.inner = inner_message
          decorator.assign_attributes inner: {note: 'updated'}
        end
      end
    end

    describe '#==' do
      it 'returns false for non-wrapper objects' do
        refute_equal 1, decorator
        refute_equal decorator, 1 # Sanity check, make sure we're testing both sides of equality
      end

      it 'returns false when messages are not equal' do
        alternate_message = message_class.new
        refute_equal alternate_message, decorator.message # Sanity check
        refute_equal decorator, Protip::Decorator.new(alternate_message, decorator.transformer)
      end

      it 'returns false when transformer are not equal' do
        alternate_transformer = Class.new do
          include Protip::Transformer
        end.new
        refute_equal alternate_transformer, transformer # Sanity check
        refute_equal transformer, Protip::Decorator.new(decorated_message, alternate_transformer)
      end

      it 'returns true when the message and transformer are equal' do
        # Stub converter equality so we aren't relying on actual equality behavior there
        alternate_transformer = transformer.clone
        transformer.expects(:==).at_least_once.with(alternate_transformer).returns(true)
        assert_equal decorator, Protip::Decorator.new(decorated_message.clone, transformer)
      end
    end

    describe '#to_h' do
      let(:transformed_value) { mock 'transformed value' }
      let(:decorated_message) do
        m = message_class.new({
          string: 'test',
          inner: inner_message_class.new(value: 1),
        })
        m.strings += %w(test1 test2)
        [2, 3].each do |i|
          m.inners.push inner_message_class.new(value: i)
        end
        m
      end

      before do
        transformer.stubs(:to_object).returns(transformed_value)
      end

      it 'contains keys for all fields of the parent message' do
        keys = %i(
          string strings inner inners inner_blank number numbers
          number_message boolean booleans google_bool_value google_bool_values
          oneof_string1 oneof_string2)
        assert_equal keys.sort, decorator.to_h.keys.sort
      end

      it 'passes along nil values' do
        hash = decorator.to_h
        assert hash.has_key?(:inner_blank)
        assert_nil hash[:inner_blank]
      end

      it 'transforms scalar messages' do
        assert_equal transformed_value, decorator.to_h[:inner]
      end

      it 'transforms repeated messages' do
        assert_equal [transformed_value, transformed_value],
          decorator.to_h[:inners]
      end

      it 'returns scalar primitives directly' do
        assert_equal 'test', decorator.to_h[:string]
      end

      it 'returns repeated primitives directly' do
        assert_equal ['test1', 'test2'], decorator.to_h[:strings]
      end

      describe 'for fields which transorm to an instance of Protip::Decorator' do
        let(:transformed_value) { Protip::Decorator.new(inner_message_class.new, transformer) }
        let(:transformed_value_to_h) { {foo: 'bar'} }
        before do
          transformed_value.stubs(:to_h).returns(transformed_value_to_h)
        end
        it 'trickles down the :to_h call on scalar messages' do
          assert_equal transformed_value_to_h, decorator.to_h[:inner]
        end
        it 'trickles down the :to_h call on repeated messages' do
          assert_equal [transformed_value_to_h, transformed_value_to_h],
            decorator.to_h[:inners]
        end
      end
    end

    describe 'getters' do
      before do
        resource_class.class_exec(transformer, inner_message_class) do |transformer, message|
          resource actions: [], message: message
          self.transformer = transformer
        end
      end

      it 'does not transform simple fields' do
        transformer.expects(:to_object).never
        assert_equal 'test', decorator.string
      end

      it 'transforms messages' do
        transformer.expects(:to_object).once.with(
          inner_message_class.new(value: 25),
          inner_message_field
        ).returns 40
        assert_equal 40, decorator.inner
      end

      it 'wraps nested resource messages in their defined resource' do
        message = decorated_message
        klass = resource_class
        decorator = Protip::Decorator.new(message, transformer, {inner: klass})
        assert_equal klass, decorator.inner.class
        assert_equal message.inner, decorator.inner.message
      end

      it 'returns nil for messages that have not been set' do
        transformer.expects(:to_object).never
        assert_equal nil, decorator.inner_blank
      end

      it 'returns the underlying assigned value for oneof fields' do
        decorated_message.oneof_string1 = 'foo'
        assert_equal 'foo', decorator.oneof_group
        decorated_message.oneof_string2 = 'bar'
        assert_equal 'bar', decorator.oneof_group
        decorated_message.oneof_string2 = 'bar'
        decorated_message.oneof_string1 = 'foo'
        assert_equal 'foo', decorator.oneof_group
      end

      it 'returns nil for oneof fields that have not been set' do
        assert_nil decorator.oneof_group
      end
    end

    describe 'attribute writer' do # generated via method_missing?

      before do
        resource_class.class_exec(transformer, inner_message_class) do |transformer, message|
          resource actions: [], message: message
          self.transformer = transformer
        end
      end

      it 'does not transform simple fields' do
        transformer.expects(:to_message).never

        decorator.string = 'test2'
        assert_equal 'test2', decorator.message.string
      end

      it 'transforms messages' do
        transformer.expects(:to_message).
          with(40, inner_message_field).
          returns(inner_message_class.new(value: 30))

        decorator.inner = 40
        assert_equal inner_message_class.new(value: 30), decorated_message.inner
      end

      it 'removes message fields when assigning nil, without transforming them' do
        transformer.expects(:to_message).never
        decorator.inner = nil
        assert_nil decorated_message.inner
      end

      it 'passes through messages without transforming them' do
        message = inner_message_class.new(value: 50)

        transformer.expects(:to_message).never
        decorator.inner = message
        assert_equal inner_message_class.new(value: 50), decorated_message.inner
      end

      it "for nested resources, sets the resource's message" do
        message = message_class.new
        klass = resource_class
        new_inner_message = inner_message_class.new(value: 50)

        resource = klass.new new_inner_message
        decorator = Protip::Decorator.new(message, transformer, {inner: klass})

        resource.expects(:message).once.returns(new_inner_message)
        decorator.inner = resource

        assert_equal new_inner_message,
          decorator.message.inner,
          'Decorator did not set its message\'s inner message value to the value of the '\
          'given resource\'s message'
      end

      it 'raises an error when setting an enum field to an undefined value' do
        assert_raises RangeError do
          decorator.number = :CHEERIOS
        end
      end

      it 'allows strings to be set for enum fields' do
        decorator.number = 'ONE'
        assert_equal :ONE, decorator.number
      end

      it 'allows symbols to be set for enum fields' do
        decorator.number = :ONE
        assert_equal :ONE, decorated_message.number
      end

      it 'allows numbers to be set for enum fields' do
        decorator.number = 1
        assert_equal :ONE, decorated_message.number
      end

      it 'allows symbolizable values to be set for enum fields' do
        m = mock
        m.stubs(:to_sym).returns(:ONE)

        decorator.number = m
        assert_equal :ONE, decorated_message.number
      end

      it 'returns the input value' do
        input_value = 'str'
        assert_equal input_value, (decorator.string = input_value)
      end
    end

    describe 'queries' do
      it 'returns the presence of scalar fields' do
        raise 'unexpected' unless decorated_message.string == 'test'
        raise 'unexpected' unless decorated_message.boolean == false
        raise 'unexpected' unless decorated_message.google_bool_value == nil

        assert_equal true, decorator.string?
        assert_equal false, decorator.boolean?
        assert_equal false, decorator.google_bool_value?

        decorated_message.string = ''
        assert_equal false, decorator.string?
      end

      it 'returns the presence of repeated fields' do
        raise 'unexpected' if decorated_message.strings.length > 0
        assert_equal false, decorator.strings?

        decorated_message.strings << 'test'
        assert_equal true, decorator.strings?
      end

      it 'returns the presence of transformed message fields' do
        raise 'unexpected' if nil == decorated_message.inner
        transformer.stubs(:to_object).returns('not empty string')
        assert_equal true, decorator.inner?

        transformer.stubs(:to_object).returns('')
        assert_equal false, decorator.inner?
      end

    end

    describe '#matches?' do
      it 'raises an error for non-enum fields' do
        assert_raises ArgumentError do
          decorator.inner?(:test)
        end
      end

      it 'raises an error for repeated enum fields' do
        assert_raises ArgumentError do
          decorator.numbers?(:test)
        end
      end

      describe 'when given a Fixnum' do
        before do
          decorator.number = :ONE
        end
        it 'returns true when the number matches the value' do
          assert decorator.number?(1)
        end
        it 'returns false when the number does not match the value' do
          refute decorator.number?(0)
        end
        it 'raises an error when the number is not a valid value for the enum' do
          assert_raises RangeError do
            decorator.number?(3)
          end
        end
      end

      describe 'when given a non-Fixnum' do
        before do
          decorator.number = :TWO
        end
        it 'returns true when its symbolized argument matches the value' do
          m = mock
          m.expects(:to_sym).returns :TWO
          assert decorator.number?(m)
        end
        it 'returns false when its symbolized argument does not match the value' do
          m = mock
          m.expects(:to_sym).returns :ONE
          refute decorator.number?(m)
        end
        it 'raises an error when its symbolized argument is not a valid value for the enum' do
          m = mock
          m.expects(:to_sym).returns :NAN
          assert_raises RangeError do
            decorator.number?(m)
          end
        end
      end

      describe 'for a wrapped enum' do
        let :enum_message do
          enum_message_class.new value: 1
        end

        before do
          transformer.stubs(:to_object).
            with(enum_message, anything).
            returns :ONE
          decorated_message.number_message = enum_message
        end

        it 'returns true when its symbolized argument matches the value' do
          m = mock
          m.expects(:to_sym).returns :ONE
          assert decorator.number_message?(m)
        end

        it 'returns false when its symbolized argument does not match the value' do
          m = mock
          m.expects(:to_sym).returns :TWO
          refute decorator.number_message?(m)
        end

        it 'returns true when a Fixnum argument matches the value' do
          assert decorator.number_message?(1)
        end

      end
    end
  end
end
