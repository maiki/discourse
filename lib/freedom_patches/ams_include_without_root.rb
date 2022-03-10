# frozen_string_literal: true

# Just ignore included associations that are to be embedded in the root instead of
# throwing an exception in AMS 0.8.x.
#
# The 0.9.0 branch does exactly this, see:
# https://github.com/rails-api/active_model_serializers/issues/377

module FreedomPatches
  module AmsIncludeWithoutRoot
    def include!(*)
      super
    rescue ActiveModel::Serializer::IncludeError
      # noop
    end

    ActiveModel::Serializer.prepend(self)
  end
end
