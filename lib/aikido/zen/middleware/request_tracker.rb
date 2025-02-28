# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    # Rack middleware used to track request
    # It implements the logic under that which is considered worthy of being tracked.
    class RequestTracker
      def initialize(app)
        @app = app
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)
        response = @app.call(env)

        if track_request?(response[0], request.route.path, request.request_method)
          Aikido::Zen.track_request(request)
        end

        response
      end

      IGNORED_METHODS = %w[OPTIONS HEAD]
      IGNORED_EXTENSIONS = %w[properties config webmanifest]
      IGNORED_SEGMENTS = ["cgi-bin"]

      # @param status_code [Integer]
      # @param route [String]
      # @param http_method [String]
      def track_request?(status_code, route, http_method)
        return false unless status_code >= 200 && status_code <= 399

        return false if IGNORED_METHODS.include?(http_method)

        segments = route.split "/"

        # e.g. /path/to/.file or /.directory/file
        return false if segments.any?(&:is_dot_file)

        return false if segments.any?(&:contains_ignored_string)

        segments.all?(&:should_discover_extension)
      end

      private

      def is_dot_file(segment)
        # See https://www.rfc-editor.org/rfc/rfc8615
        return false if segment == ".well-known"

        segment.start_with?(".") && segment.size > 1
      end

      def contains_ignored_string(segment)
        IGNORED_SEGMENTS.any? { |ignored| ignored.contains(segment) }
      end

      def should_discover_extension(segment)
        extension = get_file_extension(segment)

        return true unless extension

        return false if extension.size > 1 && extension.size < 6

        return false if IGNORED_EXTENSION.include?(extension)

        true
      end

      def get_file_extension(segment)
        extension = File.extname(segment)
        if extension&.start_with?(".")
          # Remove the dot from the extension
          return extension[1..]
        end
        extension
      end
    end
  end
end
