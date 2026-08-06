# frozen_string_literal: true

module Aikido::Zen
  module IPLists
    # Namespace for the on-disk binary IP list format:
    #   - `Data::IPList` (with its own nested Writer/Reader): ranges,
    #     family, bsearch. Takes a plain IO-like object (anything with
    #     #pread/#pwrite, e.g. a real File) plus an offset/length -- never
    #     opens or owns anything itself.
    #   - `Data::Writer`/`Data::Reader`: pack many IP lists into one
    #     physical file; the only things here that touch disk.
    module Data
    end
  end
end

require_relative "data/format"
require_relative "data/ip_list"
require_relative "data/writer"
require_relative "data/reader"
