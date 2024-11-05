# frozen_string_literal: true

require_relative "../capped_collections"

module Aikido::Zen
  # @api private
  #
  # Keeps track of the users that were seen by the app.
  class Collector::Users < Aikido::Zen::CappedMap
    def initialize(config = Aikido::Zen.config)
      super(config.max_users_tracked)
    end

    def add(actor)
      if key?(actor.id)
        self[actor.id].update
      else
        self[actor.id] = actor
      end
    end

    def each(&b)
      each_value(&b)
    end

    def as_json
      map(&:as_json)
    end
  end
end
