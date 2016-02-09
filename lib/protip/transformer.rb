require 'active_support/concern'

module Protip
  # Interface for an object that converts between messages and more complex Ruby types. Resources and wrapped
  # messages store one of these to transparently allow getting/setting of message fields as if they were
  # Ruby types.
  module Transformer
    extend ActiveSupport::Concern

    def transformable?(message_class)
      raise NotImplementedError.new(
        'Must specify whether a message of a given type can be converted to/from a Ruby object'
      )
    end

    def to_object(message, field)
      raise NotImplementedError.new('Must convert a message into a Ruby object')
    end

    def to_message(object, message_class, field)
      raise NotImplementedError.new('Must convert a Ruby object into a message of the given type')
    end
  end
end