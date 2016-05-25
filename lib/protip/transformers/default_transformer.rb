require 'protip/transformers/delegating_transformer'

module Protip
  module Transformers
    # A transformer for our built-in types.
    class DefaultTransformer < DelegatingTransformer
      def initialize
        super(::Protip::Transformers::WrappingTransformer.new, {

        })
      end
    end
  end
end
