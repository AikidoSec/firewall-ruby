namespace :ci do
  task setup: ["db:setup", "db:test:prepare"]
end
