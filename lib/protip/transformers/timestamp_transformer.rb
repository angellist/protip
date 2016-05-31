require 'protip/transformer'
require 'protip/transformers/delegating_transformer'

module Protip
  module Transformers
    class TimestampTransformer < DelegatingTransformer
      def initialize
        super
        # TODO: single-message transformers are awkward to define
        transformer = Class.new do
          include Protip::Transformer

          def to_object(message, field)
            # Using a Rational prevents rounding errors, see
            # http://stackoverflow.com/questions/16326008/accuracy-of-nanosecond-component-in-ruby-time
            ::Time.at(message.seconds, Rational(message.nanos, 1000))
          end

          def to_message(object, field)
            object = object.to_time # No-op for ::Time objects
            field.subtype.msgclass.new(
              seconds: object.to_i,
              nanos: object.nsec,
            )
          end
        end.new
        self['google.protobuf.Timestamp'] = transformer
      end
    end
  end
end
