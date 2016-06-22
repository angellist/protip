require 'bigdecimal'

require 'protip/transformer'
require 'protip/transformers/delegating_transformer'

module Protip
  module Transformers
    class BigDecimalTransformer < DelegatingTransformer
      def initialize
        super
        self['protip.messages.BigDecimalValue'] = (Class.new do
            include Protip::Transformer
            def to_object(message, field)
              BigDecimal._load(message.serialized)
            end

            def to_message(object, field)
              field.subtype.msgclass.new(serialized: BigDecimal.new(object)._dump)
            end
          end).new
      end
    end
  end
end