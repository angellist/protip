require 'test_helper'
require 'protip'

describe Protip do
  describe '.decorate' do
    let(:transformer) { mock 'transformer' }
    it 'decorates the message with the given transformer' do
      message = mock 'message'
      decorator = Protip.decorate(message, transformer)
      assert_instance_of Protip::Decorator, decorator
      assert_equal message, decorator.message
      assert_equal transformer, decorator.transformer
    end

    it 'uses the default transformer by default' do
      Protip.expects(:default_transformer).once.returns(transformer)
      message = mock 'message'
      decorator = Protip.decorate(message)
      assert_equal message, decorator.message
      assert_equal transformer, decorator.transformer
    end
  end
end
