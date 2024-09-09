# frozen_string_literal: true

require_relative "../capped_collections"

class Aikido::Zen::Stats
  # @api private
  #
  # Keeps track of the users that were seen by the app.
  class Users < Aikido::Zen::CappedMap
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
