# frozen_string_literal: true

module Aikido::Agent
  Package = Struct.new(:name, :version) do
    # @return [Boolean] whether we explicitly protect against exploits in this
    #   library.
    def supported?
      # FIXME: Implement me
      false
    end

    def as_json
      {name => {version: version.to_s, supported: supported?}}
    end
  end
end
