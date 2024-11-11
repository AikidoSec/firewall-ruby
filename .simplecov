# vim: ft=ruby

SimpleCov.start do
  # Make sure SimpleCov waits until after the tests are
  # finished to generate the coverage reports.
  self.external_at_exit = true

  enable_coverage :branch
  minimum_coverage line: 95, branch: 85

  add_filter "/test/"
end
