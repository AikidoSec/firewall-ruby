# frozen_string_literal: true

require "action_dispatch"

module Aikido::Agent
  class Request < ActionDispatch::Request
    # Yields every non-empty input in the request (whether a query param, path
    # param, or request body param).
    #
    # @return [void]
    def each_user_input
      # FIXME: This does not yet consider nested hashes
      params.each_value { |v| yield v if v.present? }
    end

    # TODO: Implement me
    def as_json
      {method: method}
    end
  end
end
