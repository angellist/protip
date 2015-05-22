require 'test_helper'

require 'protip/wrapper'

module Protip::WrapperTest # namespace for internal constants
  describe Protip::Wrapper do
    let(:converter) do
      Class.new do
        include Protip::Converter
      end.new
    end

    class InnerMessage < ::Protobuf::Message
      required :int64, :value, 1
    end
    class Message < ::Protobuf::Message
      optional InnerMessage, :inner, 1
      optional :string, :string, 2
    end

    let(:wrapped_message) do
      Message.new(inner: {value: 25}, string: 'test')
    end

    let(:wrapper) do
      Protip::Wrapper.new(wrapped_message, converter)
    end

    describe '#respond_to?' do
      it 'adds setters for message fields' do
        assert_respond_to wrapper, :string=
        assert_respond_to wrapper, :inner=
      end
      it 'adds getters for message fields' do
        assert_respond_to wrapper, :string
        assert_respond_to wrapper, :inner
      end
      it 'responds to standard defined methods' do
        assert_respond_to wrapper, :as_json
      end
      it 'does not add other setters/getters' do
        refute_respond_to wrapper, :foo=
        refute_respond_to wrapper, :foo
      end
    end

    describe '#get' do
      it 'does not convert simple fields' do
        converter.expects(:convertible?).never
        converter.expects(:to_object).never
        assert_equal 'test', wrapper.string
      end

      it 'converts convertible messages' do
        converter.expects(:convertible?).with(InnerMessage).once.returns(true)
        converter.expects(:to_object).with(InnerMessage.new(value: 25)).returns 40
        assert_equal 40, wrapper.inner
      end

      it 'wraps inconvertible messages' do
        converter.expects(:convertible?).with(InnerMessage).once.returns(false)
        converter.expects(:to_object).never
        assert_equal Protip::Wrapper.new(InnerMessage.new(value: 25), converter), wrapper.inner
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
        converter.expects(:convertible?).with(InnerMessage).once.returns(true)
        converter.expects(:to_message).with(40, InnerMessage).returns(InnerMessage.new(value: 30))

        wrapper.inner = 40
        assert_equal InnerMessage.new(value: 30), wrapper.message.inner
      end

      it 'raises an error when setting inconvertible messages' do
        converter.expects(:convertible?).with(InnerMessage).once.returns(false)
        converter.expects(:to_message).never
        assert_raises ArgumentError do
          wrapper.inner = 'cannot convert me'
        end
      end

      it 'passes through messages without checking whether they are convertible' do
        converter.expects(:convertible?).never
        converter.expects(:to_message).never

        wrapper.inner = InnerMessage.new(value: 50)
        assert_equal InnerMessage.new(value: 50), wrapper.message.inner
      end
    end
  end
end
