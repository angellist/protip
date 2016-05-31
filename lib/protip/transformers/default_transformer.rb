require 'protip/transformers/decorating_transformer'
require 'protip/transformers/delegating_transformer'
require 'protip/transformers/deprecated_transformer'
require 'protip/transformers/enum_transformer'
require 'protip/transformers/primitives_transformer'

module Protip
  module Transformers
    # A transformer for our built-in types.
    class DefaultTransformer < DelegatingTransformer
      def initialize
        # For message types that we don't recognize, just wrap them and pass
        # ourself in as the transformer for their submessages.
        super Protip::Transformers::DecoratingTransformer.new(self)

        merge! Protip::Transformers::PrimitivesTransformer.new
        merge! Protip::Transformers::EnumTransformer.new
        merge! Protip::Transformers::DeprecatedTransformer.new
      end
    end
  end
end
