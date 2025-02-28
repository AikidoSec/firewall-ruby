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

        Aikido::Zen.track_request request

        Aikido::Zen.track_discovered_route(request) if request.route && track?(
          status_code: response[0],
          route: request.route.path,
          http_method: request.request_method
        )

        response
      end

      IGNORED_METHODS = %w[OPTIONS HEAD]
      IGNORED_EXTENSIONS = %w[properties config webmanifest]
      IGNORED_SEGMENTS = ["cgi-bin"]

      # @param status_code [Integer]
      # @param route [String]
      # @param http_method [String]
      def track?(status_code:, route:, http_method:)
        return false unless status_code >= 200 && status_code <= 399

        return false if IGNORED_METHODS.include?(http_method)

        segments = route.split "/"

        # e.g. /path/to/.file or /.directory/file
        return false if segments.any? { |s| is_dot_file s }

        return false if segments.any? { |s| contains_ignored_string s }

        # Check for every file segment if it contains a file extension and if it
        # should be discovered or ignored
        segments.all? { |s| should_track_extension s }
      end

      private

      def is_dot_file(segment)
        # See https://www.rfc-editor.org/rfc/rfc8615
        return false if segment == ".well-known"

        segment.start_with?(".") && segment.size > 1
      end

      def contains_ignored_string(segment)
        IGNORED_SEGMENTS.any? { |ignored| segment.include?(ignored) }
      end

      # Ignore routes which contain file extensions
      def should_track_extension(segment)
        extension = get_file_extension(segment)

        return true unless extension

        # Do not discover files with extensions of 1 to 5 characters,
        # e.g. file.css, file.js, file.woff2
        return false if extension.size > 1 && extension.size < 6

        # Ignore some file extensions that are longer than 5 characters or shorter than 2 chars
        return false if IGNORED_EXTENSIONS.include?(extension)

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
