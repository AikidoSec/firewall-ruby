worker_processes Integer(ENV.fetch("WEB_CONCURRENCY", 2))
preload_app true
listen "127.0.0.1:#{Integer(ENV.fetch("PORT", 3000))}"

before_fork do |_server, _worker|
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

after_fork do |_server, _worker|
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end
