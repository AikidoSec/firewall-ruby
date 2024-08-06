# This file is symlinked into any Rails sample app's lib/tasks directory, to
# provide common setup tasks that need to be run in CI.

namespace :ci do
  task setup: ["db:setup", "db:test:prepare"]
end
