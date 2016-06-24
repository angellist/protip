require 'test_helper'

require 'protip/transformers/default_transformer'

describe Protip::Transformers::DefaultTransformer do
  describe '#initialize' do
    it 'initializes without errors' do
      transformer = Protip::Transformers::DefaultTransformer.new
    end
  end
end