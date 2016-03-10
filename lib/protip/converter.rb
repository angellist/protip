require 'active_support/concern'


module Protip
  module Converter
    extend ActiveSupport::Concern

    def convertible?(message_class)
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