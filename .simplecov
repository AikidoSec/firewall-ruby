# frozen_string_literal: true

# Due to dependency resolution, on Ruby 2.x we're stuck with a _very_ old
# SimpleCov version, and it doesn't really give us any benefit to run coverage
# in separate ruby versions since we don't branch on ruby version in the code.
return if RUBY_VERSION < "3.0"

SimpleCov.start do
  # Make sure SimpleCov waits until after the tests
  # are finished to generate the coverage reports.
  self.external_at_exit = true

  enable_coverage :branch
  minimum_coverage line: 95, branch: 85

  add_filter "/test/"
end

# vim: ft=ruby
