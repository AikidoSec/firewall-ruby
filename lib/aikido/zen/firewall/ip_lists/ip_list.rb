# frozen_string_literal: true

require "json"

module Aikido::Zen
  class Firewall
    class IPLists
      class IPList
        attr_reader :key
        attr_reader :source
        attr_reader :description

        # @param ip_list [Aikido::Zen::IPLists::IPList]
        def initialize(ip_list)
          metadata = JSON.parse(ip_list.data, symbolize_names: true)

          @key = metadata.fetch(:key)
          @source = metadata.fetch(:source)
          @description = metadata.fetch(:description)
        end
      end
    end
  end
end
