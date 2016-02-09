require 'protip/transformer'
require 'protip/messages/active_support/time_with_zone'

module Protip
  module Transformers
    module ActiveSupport
      module TimeWithZoneTransformer
        include Protip::Transformer

        def transformable?(message_class)
          message_class == ::Protip::Messages::ActiveSupport::TimeWithZone
        end

        def to_object(message)
          ActiveSupport::TimeWithZone.new(
            Time.at(message.utc_timestamp).utc,
            ActiveSupport::TimeZone.new(message.time_zone_name)
          )
        end

        def to_message(value, message_class)
          if !value.is_a?(::ActiveSupport::TimeWithZone) && (value.is_a?(Time) || value.is_a?(DateTime))
            value = ::ActiveSupport::TimeWithZone.new(value.to_time.utc, ::ActiveSupport::TimeZone.new('UTC'))
          end
          raise ArgumentError unless value.is_a?(::ActiveSupport::TimeWithZone)

          message_class.new(
            utc_timestamp: value.to_i,
            time_zone_name: value.time_zone.name,
          )
        end
      end
    end
  end
end