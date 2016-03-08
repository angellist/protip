require 'protip/client'
require 'protip/resource'

# Register the mime type with Rails, if Rails exists.
if defined?(Mime::Type)
  Mime::Type.register 'application/x-protobuf', :protobuf
end

module Protip
  # Temporary placeholder until Ruby support for field options in protobuf is
  # rolled out. Once that happens, this will be configurable in protobuf:
  #
  # = Protobuf Example
  #
  #   message Foo {
  #     enum State {
  #       CREATED=0;
  #     }
  #     protip.messages.EnumValue state = 1 [(protip_enum) = "Foo.State"]
  #   }
  def self.set_enum(field, enum_name)
    field.instance_variable_set :'@_protip_enum_name', enum_name.to_s
  end
end