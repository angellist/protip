require 'bigdecimal'
require 'bigdecimal/util' # Pulls in the rational -> bigdecimal conversion

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
              Rational(message.numerator, message.denominator).to_d(message.precision)
            end

            def to_message(object, field)
              object = BigDecimal(object)
              rational = object.to_r
              field.subtype.msgclass.new(
                numerator: rational.numerator,
                denominator: rational.denominator,
                precision: object.precs[0], # This is the current precision of the decimal
              )
            end
          end).new
      end
    end
  end
end
