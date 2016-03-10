require 'protip/client'
require 'protip/resource'

# Register the mime type with Rails, if Rails exists.
if defined?(Mime::Type)
  Mime::Type.register 'application/x-protobuf', :protobuf
end
