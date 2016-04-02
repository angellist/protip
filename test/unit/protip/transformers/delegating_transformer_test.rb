require 'test_helper'

require 'protip/transformers/delegating_transformer'

describe Protip::Transformers::DelegatingTransformer do
  %i(transformer1 transformer2).each do |name|
    let(name) { mock.responds_like_instance_of Protip::Transformer }
  end
  let(:delegating_transformer) do
    t = Protip::Transformers::DelegatingTransformer.new
    t.add transformer1
    t.add transformer2
    t
  end

  describe '#transformable?' do
    let(:message_class) { mock.responds_like_instance_of Class }
    it 'returns true if any of the sub-transformers return true' do
      transformer1.expects(:transformable?)
        .with(message_class).at_most_once.returns(false)
      transformer2.expects(:transformable?)
        .with(message_class).at_most_once.returns(true)
      assert delegating_transformer.transformable?(message_class)
    end
  end
end
