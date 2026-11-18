require 'erb'

module Protip
  module Resource
    module MemberPath
      def self.build(resource_class, id)
        segment = id.to_s
        if segment.empty? || segment == '.' || segment == '..'
          raise ArgumentError.new('Invalid Protip member ID')
        end
        "#{resource_class.base_path}/#{ERB::Util.url_encode(segment)}"
      end
    end
  end
end
