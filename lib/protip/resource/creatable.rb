module Protip
  module Resource
    # Mixin for a resource that has an active `:create` action. Should be treated as private,
    # and will be included automatically when appropriate.
    module Creatable
      private
      # POST the resource to the server and update our internal message. Private, since
      # we should generally do this through the `save` method.
      def create!
        raise RuntimeError.new("Can't re-create a persisted object") if persisted?
        self.message = self.class.client.request path: self.class.base_path,
          method: :post,
          message: message,
          response_type: self.class.message
      end
    end
  end
end
