module Protip
  module Resource
    # Mixin for a resource that has an active `:destroy` action. Should be treated as private,
    # and will be included automatically when appropriate.
    module Destroyable
      def destroy
        raise RuntimeError.new("Can't destroy a non-persisted object") if !persisted?
        self.message = self.class.client.request path: "#{self.class.base_path}/#{id}",
          method: :delete,
          message: nil,
          response_type: self.class.message
      end
    end
  end
end
