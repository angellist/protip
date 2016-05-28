require 'protip/client'
require 'protip/resource'

# Register the mime type with Rails, if Rails exists.
if defined?(Mime::Type)
  Mime::Type.register 'application/x-protobuf', :protobuf
end

module Protip
  def self.default_transformer
    @default_transformer ||= Protip::Transformers::DefaultTransformer.new
  end

  def self.decorate(message, transformer = Protip.default_transfomer)
    Protip::Decorator.new(message, transformer)
  end
end
