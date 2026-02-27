# frozen_string_literal: true

module Aikido::Zen
  class RuntimeSettings::DomainSettings
    def self.none
      @no_settings ||= new(mode: :block)
    end

    def self.from_json(data)
      new(
        mode: data["mode"]&.to_sym
      )
    end

    attr_reader :mode

    def initialize(mode:)
      raise ArgumentError, "mode must be either :block or :allow" unless [:block, :allow].include?(mode)

      @mode = mode
    end

    def block?
      @mode == :block
    end
  end
end
