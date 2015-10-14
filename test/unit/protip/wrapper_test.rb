require 'test_helper'

require 'google/protobuf'
require 'protip/converter'
require 'protip/wrapper'

module Protip::WrapperTest # namespace for internal constants
  describe Protip::Wrapper do
    let(:converter) do
      Class.new do
        include Protip::Converter
      end.new
    end
    let :pool do
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

        add_message 'message' do
          optional :inner, :message, 1, 'inner_message'
          optional :string, :string, 2

          repeated :inners, :message, 3, 'inner_message'
          repeated :strings, :string, 4

          optional :inner_blank, :message, 5, 'inner_message'

          optional :number, :enum, 6, 'number'
          repeated :numbers, :enum, 7, 'number'
        end
      end
      pool
    end

    %w(inner_message message).each do |name|
      let(:"#{name}_class") do
        pool.lookup(name).msgclass
      end
    end

    let(:wrapped_message) do
      message_class.new(inner: inner_message_class.new(value: 25), string: 'test')
    end

    let(:wrapper) do
      Protip::Wrapper.new(wrapped_message, converter)
    end

    describe '#respond_to?' do
      it 'adds setters for message fields' do
        assert_respond_to wrapper, :string=
        assert_respond_to wrapper, :inner=
        assert_respond_to wrapper, :inner_blank=
      end
      it 'adds getters for message fields' do
        assert_respond_to wrapper, :string
        assert_respond_to wrapper, :inner
        assert_respond_to wrapper, :inner_blank
      end
      it 'adds queries for scalar enum fields' do
        assert_respond_to wrapper, :number?
      end
      it 'does not add queries for repeated enum fields' do
        refute_respond_to wrapper, :numbers?
      end
      it 'does not add queries for non-enum fields' do
        refute_respond_to wrapper, :inner?
      end
      it 'responds to standard defined methods' do
        assert_respond_to wrapper, :as_json
      end
      it 'does not add other setters/getters/queries' do
        refute_respond_to wrapper, :foo=
        refute_respond_to wrapper, :foo
        refute_respond_to wrapper, :foo?
      end
      it 'does not add methods which partially match message fields' do
        refute_respond_to wrapper, :xinner
        refute_respond_to wrapper, :xinner=
        refute_respond_to wrapper, :xnumber?
        refute_respond_to wrapper, :innerx
        refute_respond_to wrapper, :innerx=
        refute_respond_to wrapper, :'inner=x'
        refute_respond_to wrapper, :numberx?
        refute_respond_to wrapper, :'number?x'
      end
    end

    describe '#build' do
      it 'raises an error when building a primitive field' do
        assert_raises RuntimeError do
          wrapper.build(:string)
        end
      end

      it 'raises an error when building a repeated primitive field' do
        assert_raises RuntimeError do
          wrapper.build(:strings)
        end
      end

      # TODO: How to add a new message to a repeated message field?

      it 'raises an error when building a convertible message' do
        converter.stubs(:convertible?).with(inner_message_class).returns(true)
        assert_raises RuntimeError do
          wrapper.build(:inner)
        end
      end

      describe 'with an inconvertible message field' do
        let(:wrapped_message) { message_class.new }

        before do
          converter.stubs(:convertible?).with(inner_message_class).returns(false)
        end

        it 'builds the message when no attributes are provided' do
          assert_nil wrapped_message.inner # Sanity check
          wrapper.build(:inner)
          assert_equal inner_message_class.new, wrapped_message.inner
        end

        it 'overwrites the message if it exists' do
          wrapped_message.inner = inner_message_class.new(value: 4)
          wrapper.build(:inner)
          assert_equal inner_message_class.new, wrapped_message.inner
        end

        it 'delegates to #assign_attributes if attributes are provided' do
          Protip::Wrapper.any_instance.expects(:assign_attributes).once.with({value: 40})
          wrapper.build(:inner, value: 40)
        end

        it 'returns the built message' do
          built = wrapper.build(:inner)
          assert_equal wrapper.inner, built
        end
      end
    end

    describe '#assign_attributes' do
      it 'assigns primitive fields directly' do
        wrapper.assign_attributes string: 'another thing'
        assert_equal 'another thing', wrapped_message.string
      end

      it 'assigns repeated primitive fields from an enumerator' do
        wrapper.assign_attributes strings: ['one', 'two']
        assert_equal ['one', 'two'], wrapped_message.strings
      end

      describe 'when assigning convertible message fields' do
        before do
          converter.stubs(:convertible?).with(inner_message_class).returns(true)
        end

        it 'converts scalar Ruby values to protobuf messages' do
          converter.expects(:to_message).once.with(45, inner_message_class).returns(inner_message_class.new(value: 43))
          wrapper.assign_attributes inner: 45
          assert_equal inner_message_class.new(value: 43), wrapped_message.inner
        end

        it 'converts repeated Ruby values to protobuf messages' do
          invocation = 0
          converter.expects(:to_message).twice.with do |value|
            invocation += 1
            value == invocation
          end.returns(inner_message_class.new(value: 43), inner_message_class.new(value: 44))
          wrapper.assign_attributes inners: [1, 2]
          assert_equal [inner_message_class.new(value: 43), inner_message_class.new(value: 44)], wrapped_message.inners
        end

        it 'allows messages to be assigned directly' do
          message = inner_message_class.new
          wrapper.assign_attributes inner: message
          assert_same message, wrapper.message.inner
        end
      end

      it 'returns nil' do
        assert_nil wrapper.assign_attributes({})
      end

      describe 'when assigning inconvertible message fields' do
        before do
          converter.stubs(:convertible?).with(inner_message_class).returns(false)
        end

        it 'sets multiple attributes' do
          wrapper.assign_attributes string: 'test2', inner: {value: 50}
          assert_equal 'test2', wrapped_message.string
          assert_equal inner_message_class.new(value: 50), wrapped_message.inner
        end

        it 'updates inconvertible message fields which have already been built' do
          wrapped_message.inner = inner_message_class.new(value: 60)
          wrapper.assign_attributes inner: {note: 'updated'}
          assert_equal inner_message_class.new(value: 60, note: 'updated'), wrapped_message.inner
        end

        it 'delegates to #assign_attributes on a nested wrapper when setting nested attributes on inconvertible message fields' do
          inner = mock
          field = wrapped_message.class.descriptor.detect{|f| f.name.to_sym == :inner}
          raise 'unexpected' if !field
          wrapper.stubs(:get).with(field).returns(inner)
          inner.expects(:assign_attributes).once.with(value: 50, note: 'noted')
          wrapper.assign_attributes inner: {value: 50, note: 'noted'}
        end

        it 'allows messages to be assigned directly' do
          message = inner_message_class.new
          wrapper.assign_attributes inner: message
          assert_same message, wrapper.message.inner
        end
      end
    end

    describe '#==' do
      it 'returns false for non-wrapper objects' do
        refute_equal 1, wrapper
        refute_equal wrapper, 1 # Sanity check, make sure we're testing both sides of equality
      end

      it 'returns false when messages are not equal' do
        alternate_message = message_class.new
        refute_equal alternate_message, wrapper.message # Sanity check
        refute_equal wrapper, Protip::Wrapper.new(alternate_message, wrapper.converter)
      end

      it 'returns false when converters are not equal' do
        alternate_converter = Class.new do
          include Protip::Converter
        end.new
        refute_equal alternate_converter, converter # Sanity check
        refute_equal wrapper, Protip::Wrapper.new(wrapped_message, alternate_converter)
      end

      it 'returns true when the message and converter are equal' do
        # Stub converter equality so we aren't relying on actual equality behavior there
        alternate_converter = converter.clone
        converter.expects(:==).at_least_once.with(alternate_converter).returns(true)
        assert_equal wrapper, Protip::Wrapper.new(wrapped_message.clone, converter)
      end
    end

    describe '#convert' do
      let :wrapped_message do
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
        converter.stubs(:convertible?).with(message_class).returns false
      end

      it 'never checks the convertibility of the top-level message' do
        converter.expects(:convertible?).with(message_class).never
        converter.stubs(:convertible?).with(inner_message_class).returns false
        assert_instance_of Hash, wrapper.to_h
      end

      describe 'with a nested convertible message' do
        before do
          converter.stubs(:convertible?).with(inner_message_class).returns true
          [1, 2, 3].each{|i| converter.stubs(:to_object).with(inner_message_class.new(value: i)).returns(i)}
        end
        it 'returns a hash with the nested message converted' do
          assert_equal 1, wrapper.to_h[:inner]
        end
        it 'converts a repeated instance of the nested message to an array' do
          assert_equal [2, 3], wrapper.to_h[:inners]
        end
      end

      describe 'with a nested inconvertible message' do
        before do
          converter.stubs(:convertible?).with(inner_message_class).returns false
        end

        it 'contains keys for all fields of the parent message' do
          assert_equal %i(string strings inner inners inner_blank number numbers).sort, wrapper.to_h.keys.sort
        end
        it 'assigns nil for missing nested messages' do
          hash = wrapper.to_h
          assert hash.has_key?(:inner_blank)
          assert_nil hash[:inner_blank]
        end
        it 'assigns a hash for a scalar instance of the inconvertible message' do
          assert_equal({value: 1, note: ''}, wrapper.to_h[:inner])
        end
        it 'assigns an array of hashes for a repeated instance of the inconvertible message' do
          assert_equal([{value: 2, note: ''}, {value: 3, note: ''}], wrapper.to_h[:inners])
        end
        it 'assigns primitive fields directly' do
          assert_equal 'test', wrapper.to_h[:string]
        end
        it 'assigns an array for repeated primitive fields' do
          assert_equal %w(test1 test2), wrapper.to_h[:strings]
        end
      end
    end

    describe '#get' do
      it 'does not convert simple fields' do
        converter.expects(:convertible?).never
        converter.expects(:to_object).never
        assert_equal 'test', wrapper.string
      end

      it 'converts convertible messages' do
        converter.expects(:convertible?).with(inner_message_class).once.returns(true)
        converter.expects(:to_object).once.with(inner_message_class.new(value: 25)).returns 40
        assert_equal 40, wrapper.inner
      end

      it 'wraps inconvertible messages' do
        converter.expects(:convertible?).with(inner_message_class).once.returns(false)
        converter.expects(:to_object).never
        assert_equal Protip::Wrapper.new(inner_message_class.new(value: 25), converter), wrapper.inner
      end

      it 'returns nil for messages that have not been set' do
        converter.expects(:convertible?).never
        converter.expects(:to_object).never
        assert_equal nil, wrapper.inner_blank
      end
    end

    describe '#set' do
      it 'does not convert simple fields' do
        converter.expects(:convertible?).never
        converter.expects(:to_message).never

        wrapper.string = 'test2'
        assert_equal 'test2', wrapper.message.string
      end

      it 'converts convertible messages' do
        converter.stubs(:convertible?).with(inner_message_class).returns(true)
        converter.expects(:to_message).with(40, inner_message_class).returns(inner_message_class.new(value: 30))

        wrapper.inner = 40
        assert_equal inner_message_class.new(value: 30), wrapper.message.inner
      end

      it 'removes message fields when assigning nil' do
        converter.stubs(:convertible?).with(inner_message_class).returns(false)
        converter.expects(:to_message).never

        wrapper.inner = nil
        assert_equal nil, wrapper.message.inner
      end

      it 'raises an error when setting inconvertible messages' do
        converter.stubs(:convertible?).with(inner_message_class).returns(false)
        converter.expects(:to_message).never
        assert_raises ArgumentError do
          wrapper.inner = 'cannot convert me'
        end
      end

      it 'passes through messages without checking whether they are convertible' do
        converter.expects(:convertible?).once.returns(true)
        message = inner_message_class.new(value: 50)

        converter.expects(:convertible?).never
        converter.expects(:to_message).never
        wrapper.inner = message
        assert_equal inner_message_class.new(value: 50), wrapper.message.inner
      end

      it 'raises an error when setting an enum field to an undefined value' do
        assert_raises RangeError do
          wrapper.number = :NAN
        end
      end

      it 'allows strings to be set for enum fields' do
        wrapper.number = 'ONE'
        assert_equal :ONE, wrapper.number
      end

      it 'allows symbols to be set for enum fields' do
        wrapper.number = :ONE
        assert_equal :ONE, wrapper.number
      end

      it 'allows numbers to be set for enum fields' do
        wrapper.number = 1
        assert_equal :ONE, wrapper.number
      end

      it 'allows symbolizable values to be set for enum fields' do
        m = mock
        m.stubs(:to_sym).returns(:ONE)

        wrapper.number = m
        assert_equal :ONE, wrapper.number
      end
    end

    describe '#matches?' do
      it 'is not defined for non-enum fields' do
        assert_raises NoMethodError do
          wrapper.inner?(:test)
        end
      end

      it 'is not defined for repeated enum fields' do
        assert_raises NoMethodError do
          wrapper.numbers?(:test)
        end
      end

      describe 'when given a Fixnum' do
        before do
          wrapper.number = :ONE
        end
        it 'returns true when the number matches the value' do
          assert wrapper.number?(1)
        end
        it 'returns false when the number does not match the value' do
          refute wrapper.number?(0)
        end
        it 'raises an error when the number is not a valid value for the enum' do
          assert_raises RangeError do
            wrapper.number?(3)
          end
        end
      end

      describe 'when given a non-Fixnum' do
        before do
          wrapper.number = :TWO
        end
        it 'returns true when its symbolized argument matches the value' do
          m = mock
          m.expects(:to_sym).returns :TWO
          assert wrapper.number?(m)
        end
        it 'returns false when its symbolized argument does not match the value' do
          m = mock
          m.expects(:to_sym).returns :ONE
          refute wrapper.number?(m)
        end
        it 'raises an error when its symbolized argument is not a valid value for the enum' do
          m = mock
          m.expects(:to_sym).returns :NAN
          assert_raises RangeError do
            wrapper.number?(m)
          end
        end
      end
    end
  end
end
