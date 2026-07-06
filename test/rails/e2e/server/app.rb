# frozen_string_literal: true

require "sinatra"
require "json"

require_relative "lib/zen/apps"
require_relative "lib/zen/config"
require_relative "lib/zen/events"
require_relative "lib/zen/streams"

configure do
  set :port, ENV.fetch("PORT", 4567).to_i
  set :bind, "0.0.0.0"
  set :logging, true
end

Zen::Streams.start_pinger

before do
  content_type :json
end

helpers do
  def authenticate!
    token = request.env["HTTP_AUTHORIZATION"]
    halt 401, {"message" => "Token is required"}.to_json unless token

    app = Zen::Apps.find(token)
    halt 401, {"message" => "Invalid token"}.to_json unless app

    @app = app
  end

  def json_body
    body = request.body.read
    JSON.parse(body) unless body.empty?
  end

  def geo_list(ips)
    {
      "key" => "geoip/Belgium;BE",
      "source" => "geoip",
      "description" => "geo restrictions",
      "ips" => ips
    }
  end
end

post "/api/runtime/apps" do
  app = Zen::Apps.create

  body = json_body

  if body.is_a?(Hash)
    extra = body.slice("failureRate", "timeout").select { |_, v| v.is_a?(Numeric) }

    Zen::Config.update(app, extra) if extra.any?
  end

  {"token" => app.token}.to_json
end

delete "/api/runtime/apps" do
  authenticate!

  Zen::Apps.remove(@app)
  Zen::Streams.close_all(@app.id)

  {"ok" => true}.to_json
end

get "/api/runtime/config" do
  authenticate!

  config = Zen::Config.get(@app).dup

  # Strip test-only keys before returning to the library.
  config.delete("failureRate")
  config.delete("timeout")

  config.to_json
end

post "/api/runtime/config" do
  authenticate!

  body = json_body

  halt 400, {"message" => "Request body is missing or invalid"}.to_json unless body.is_a?(Hash) && !body.empty?

  {"success" => Zen::Config.update(@app, body)}.to_json
end

get "/config" do
  authenticate!

  config = Zen::Config.get(@app)

  {"serviceId" => @app.id, "configUpdatedAt" => config["configUpdatedAt"]}.to_json
end

get "/api/runtime/stream" do
  authenticate!

  content_type "text/event-stream"
  headers "Cache-Control" => "no-cache", "Connection" => "keep-alive"

  messages = Queue.new

  # Under Puma, Sinatra's stream(:keep_open) re-invokes this block in a loop.
  stream(:keep_open) do |out|
    Zen::Streams.register(@app.id, out, messages)
    sub = Zen::Config.subscribe(@app.id) { messages << :config_updated }

    messages << :config_updated

    out.callback do
      Zen::Config.unsubscribe(@app.id, sub)
      Zen::Streams.remove(@app.id, out)

      messages.close
    end

    write_event = lambda do |data|
      out << data
    rescue
      out.close
    end

    # Blocking on the queue prevents a busy wait while the connection is open.
    while (message = messages.pop) && !out.closed?
      case message
      when :ping
        write_event.call(": ping\n\n")
      when :config_updated
        config = Zen::Config.get(@app)

        json = {
          "serviceId" => @app.id,
          "configUpdatedAt" => config["configUpdatedAt"]
        }.to_json

        write_event.call("event: config-updated\ndata: #{json}\n\n")
      end
    end
  end
end

post "/api/runtime/stream/disconnect" do
  authenticate!

  Zen::Streams.close_all(@app.id)

  {"ok" => true}.to_json
end

get "/api/runtime/events" do
  authenticate!

  Zen::Events.list(@app).to_json
end

post "/api/runtime/events" do
  authenticate!

  body = json_body || {}

  if body["type"] == "detected_attack"
    config = Zen::Config.get(@app)

    # Simulate the server dropping the connection to test library retry logic.
    if (failure_rate = config["failureRate"].to_f) > 0 && rand < failure_rate
      env["rack.hijack"].call if env["rack.hijack?"]

      begin
        env["rack.hijack_io"].close
      rescue
        nil
      end

      # Puma ignores the response for a hijacked connection
      return
    end

    sleep(rand * config["timeout"].to_i / 1000) if config["timeout"].to_i > 0
  end

  Zen::Events.capture(body, @app)

  if body["type"] == "detected_attack"
    {"success" => true}.to_json
  else
    Zen::Config.get(@app).to_json
  end
end

get "/api/runtime/firewall/lists" do
  authenticate!

  # The real API requires gzip - enforced here so tests catch a missing header.
  unless (request.env["HTTP_ACCEPT_ENCODING"] || "").downcase.include?("gzip")
    halt 400, {
      "success" => false,
      "error" => "Accept-Encoding header must include 'gzip' for firewall lists endpoint"
    }.to_json
  end

  blocked_ips = Zen::Config.blocked_ips(@app)
  allowed_ips = Zen::Config.allowed_ips(@app)
  monitored_ips = Zen::Config.monitored_ips(@app)

  {
    "success" => true,
    "serviceId" => @app.id,
    "blockedIPAddresses" => blocked_ips.any? ? [geo_list(blocked_ips)] : [],
    "allowedIPAddresses" => allowed_ips.any? ? [geo_list(allowed_ips)] : [],
    "monitoredIPAddresses" => monitored_ips.any? ? [geo_list(monitored_ips)] : [],
    "blockedUserAgents" => Zen::Config.blocked_user_agents(@app),
    "monitoredUserAgents" => Zen::Config.monitored_user_agents(@app),
    "userAgentDetails" => Zen::Config.user_agent_details(@app)
  }.to_json
end

post "/api/runtime/firewall/lists" do
  authenticate!

  body = json_body

  halt 400, {"message" => "Request body is missing or invalid"}.to_json unless body.is_a?(Hash) && !body.empty?

  halt 400, {"message" => "blockedIPAddresses is missing or invalid"}.to_json unless body["blockedIPAddresses"].is_a?(Array)

  Zen::Config.update_blocked_ips(@app, body["blockedIPAddresses"])
  Zen::Config.update_blocked_user_agents(@app, body["blockedUserAgents"]) if body["blockedUserAgents"].is_a?(String)
  Zen::Config.update_allowed_ips(@app, body["allowedIPAddresses"]) if body["allowedIPAddresses"].is_a?(Array)
  Zen::Config.update_monitored_user_agents(@app, body["monitoredUserAgents"]) if body["monitoredUserAgents"].is_a?(String)
  Zen::Config.update_monitored_ips(@app, body["monitoredIPAddresses"]) if body["monitoredIPAddresses"].is_a?(Array)
  Zen::Config.update_user_agent_details(@app, body["userAgentDetails"]) if body["userAgentDetails"].is_a?(Array)

  {"success" => true}.to_json
end
