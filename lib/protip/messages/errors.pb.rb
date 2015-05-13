# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf/message'

module Protip
  module Messages

    ##
    # Message Classes
    #
    class Errors < ::Protobuf::Message; end
    class FieldError < ::Protobuf::Message; end


    ##
    # Message Fields
    #
    class Errors
      repeated :string, :messages, 1
      repeated ::Protip::Messages::FieldError, :field_errors, 2
    end

    class FieldError
      optional :string, :field, 1
      optional :string, :message, 2
    end

  end

end

