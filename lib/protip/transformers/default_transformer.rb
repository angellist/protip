require 'protip/transformers/delegating_transformer'

module Protip
  module Transformers
    # A transformer for our built-in types.
    class DefaultTransformer < DelegatingTransformer
      def initialize
        super
        add ::Protip::Transformers::WellKnownTypesTransformer.new
        add ::Protip::Transformers::ActiveSupport::TimeWithZoneTransformer.new
      end
    end
  end
end