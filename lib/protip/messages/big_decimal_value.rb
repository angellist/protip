# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: protip/messages/big_decimal_value.proto

require 'google/protobuf'

Google::Protobuf::DescriptorPool.generated_pool.build do
  add_message "protip.messages.BigDecimalValue" do
    optional :numerator, :int64, 1
    optional :denominator, :uint64, 2
    optional :precision, :uint32, 3
  end
end

module Protip
  module Messages
    BigDecimalValue = Google::Protobuf::DescriptorPool.generated_pool.lookup("protip.messages.BigDecimalValue").msgclass
  end
end
