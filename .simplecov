# frozen_string_literal: true

# Due to dependency resolution, on Ruby 2.x we're stuck with a _very_ old
# SimpleCov version, and it doesn't really give us any benefit to run coverage
# in separate ruby versions since we don't branch on ruby version in the code.
return if RUBY_VERSION < "3.0"
return if ENV["DISABLE_COVERAGE"] == "true"

SimpleCov.start do
  # Make sure SimpleCov waits until after the tests
  # are finished to generate the coverage reports.
  self.external_at_exit = true

  enable_coverage :branch
  minimum_coverage line: 95, branch: 85

  add_filter "/test/"

  # WebMock excludes EM-HTTP-Request on Ruby 3.4:
  # https://github.com/c960657/webmock/commit/34d16285dbcc574c90b273a89f16cb5fb9f4222a
  if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.4.0") && Gem.loaded_specs["em-http-request"].version <= Gem::Version.new("1.1.7")
    add_filter "lib/aikido/zen/sinks/em_http.rb"
  end
end

# vim: ft=ruby
