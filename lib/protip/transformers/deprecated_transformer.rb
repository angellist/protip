require 'protip/transformer'
require 'protip/transformers/delegating_transformer'

require 'active_support/time_with_zone'
require 'money'

# Temporary transformer for types that will be moved out to
# user extensions.
module Protip
  module Transformers
    class DeprecatedTransformer < DelegatingTransformer

      def initialize
        super
        self['protip.messages.Currency'] = CurrencyTransformer.new
        self['protip.messages.Money'] = MoneyTransformer.new
        self['protip.messages.Date'] = DateTransformer.new
        self['protip.messages.Range'] = RangeTransformer.new
        self['protip.messages.ActiveSupport.TimeWithZone'] = TimeWithZoneTransformer.new
      end

      class CurrencyTransformer
        include Protip::Transformer
        def to_object(message, field)
          message.currency_code
        end
        def to_message(object, field)
          field.subtype.msgclass.new(currency_code: object)
        end
      end

      class MoneyTransformer
        include Protip::Transformer
        def to_object(message, field)
          ::Money.new(message.amount_cents, message.currency.currency_code)
        end
        def to_message(object, field)
          money = object.to_money
          currency = Protip::Messages::Currency.new(currency_code: money.currency.iso_code.to_sym)
          field.subtype.msgclass.new(
            amount_cents: money.fractional,
            currency: currency,
          )
        end
      end

      class DateTransformer
        include Protip::Transformer
        def to_object(message, field)
          ::Date.new(message.year, message.month, message.day)
        end
        def to_message(object, field)
          raise ArgumentError unless object.is_a?(::Date)
          field.subtype.msgclass.new(year: object.year, month: object.month, day: object.day)
        end
      end

      class RangeTransformer
        include Protip::Transformer
        def to_object(message, field)
          message.begin..message.end
        end
        def to_message(object, field)
          field.subtype.msgclass.new(begin: object.begin.to_i, end: object.end.to_i)
        end
      end

      class TimeWithZoneTransformer
        include Protip::Transformer
        def to_object(message, field)
          ActiveSupport::TimeWithZone.new(
            Time.at(message.utc_timestamp).utc,
            ActiveSupport::TimeZone.new(message.time_zone_name)
          )
        end
        def to_message(object, field)
          if !object.is_a?(::ActiveSupport::TimeWithZone) && (object.is_a?(Time) || object.is_a?(DateTime))
            object = ::ActiveSupport::TimeWithZone.new(object.to_time.utc, ::ActiveSupport::TimeZone.new('UTC'))
          end
          raise ArgumentError unless object.is_a?(::ActiveSupport::TimeWithZone)

          field.subtype.msgclass.new(
            utc_timestamp: object.to_i,
            time_zone_name: object.time_zone.name,
          )
        end
      end
    end
  end
end
