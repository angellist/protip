module Protip
  module Resource
    # Mixin for a resource that has an active `:update` action. Should be treated as private,
    # and will be included automatically when appropriate.
    module Updatable
      private
      # PUT the resource on the server and update our internal message. Private, since
      # we should generally do this through the `save` method.
      def update!
        raise RuntimeError.new("Can't update a non-persisted object") if !persisted?
        self.message = self.class.client.request path: "#{self.class.base_path}/#{id}",
          method: Net::HTTP::Put,
          message: message,
          response_type: self.class.message
      end
    end

  end
end