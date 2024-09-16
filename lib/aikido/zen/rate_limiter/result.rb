module Aikido::Zen
  # Holds the stats after checking if a request should be rate limited, which
  # will be added to the Rack env.
  class RateLimiter::Result
    # @return [String] the output of the configured discriminator block, used to
    #   uniquely identify a client (e.g. the remote IP).
    attr_reader :discriminator

    # @return [Integer] number of requests for the client in the current window.
    attr_reader :current_requests

    # @return [Integer] configured max number of requests per client.
    attr_reader :max_requests

    # @return [Integer] number of seconds remaining until the window resets.
    attr_reader :time_remaining

    def initialize(throttled:, discriminator:, current_requests:, max_requests:, time_remaining:)
      @throttled = throttled
      @discriminator = discriminator
      @current_requests = current_requests
      @max_requests = max_requests
      @time_remaining = time_remaining
    end

    # @return [Boolean] whether the current request was throttled or not.
    def throttled?
      @throttled
    end
  end
end
