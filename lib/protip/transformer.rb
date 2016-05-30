module Protip
  # Interface for an object that converts between messages and more complex Ruby types. Resources and wrapped
  # messages store one of these to transparently allow getting/setting of message fields as if they were
  # Ruby types.
  module Transformer
    def to_object(message, field)
      raise NotImplementedError.new('Must convert a message into a Ruby object')
    end

    def to_message(object, field)
      raise NotImplementedError.new('Must convert a Ruby object into a message of the given type')
    end
  end
end
