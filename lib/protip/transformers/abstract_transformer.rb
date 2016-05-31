require 'protip/transformer'

module Protip
  module Transformers
    # Instantiable version of the +::Protip::Transformer+ concern,
    # for when we need a placeholder transformer object.
    class AbstractTransformer
      include ::Protip::Transformer
    end
  end
end
