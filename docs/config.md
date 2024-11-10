# Configuring Zen

Zen allows configuring a few settings in the gem. These can be accessed by
changing values on the `Aikido::Zen.config` object, which you can do from
your app's startup file (like an initializer in Rails, or `config.ru` in
other Rack-based apps).

## Disable Zen

In order to fully turn off Zen and prevent it from intercepting any requests or
reporting back to the Aikido servers, set `AIKIDO_DISABLED=true` in your
environment, or set `Aikido::Zen.config.disabled = true`.

(We recommend the ENV variable as you can normally change this easily without
requiring a full deploy.)

## Blocking mode

In order to have Aikido block requests that look like attacks, you can set
`AIKIDO_BLOCKING=true` in your environment, or set
`Aikido::Zen.config.blocking_mode = true`.

(We recommend the ENV variable as you can normally change this easily without
requiring a full deploy.)

## API Token for reporting to your Aikido Security dashboard

To get the most out of Zen, you'll want to enable reporting to the Aikido
Security dashboard. To do this, you can set your Aikido Security token in the
environment via `AIKIDO_TOKEN=AIKIDO_RUNTIME_...`.

Alternatively, if you have your token in some other credential store, you can
set it via `Aikido::Zen.config.token = <token>`.

**NOTE**: Never commit your token to the source code repository in plain text.

## Logger

Zen logs to standard output by default. You can change this by changing the
instead of the `logger` used by Zen:

``` ruby
Aikido::Zen.logger = Logger.new("zen.log", progname: "zen")
```

## Rate-limiting responses

If you're using the rate-limiting features of Zen, you can configure the
response we send users when they are rate-limited with a Proc that returns
a Rack-compatible response tuple, like this:

``` ruby
Aikido::Zen.rate_limited_responder = ->(request) {
  # Here, request is an instance of Aikido::Zen::Request, which follows the
  # underlying Rack::Request (or ActionDispatch::Request in Rails) API.
  [429, {"Content-Type" => "application/json"}, ['{"error":"rate_limited"}']]
}
```

By default, Zen emits a `text/plain` 429 response that says "Too many requests".

### Providing details about the rate limiting

When rate-limiting is enabled, Zen will add an object to the Rack env with
details about the request and how it was rate limited. You can use this
information to provide useful headers in the response for well-behaved clients:

``` ruby
Aikido::Zen.rate_limited_responder = ->(request) {
  rate_limited = request.env["aikido.rate_limiting"]

  headers = {
    "RateLimit-Limit" => rate_limited.max_requests,
    "RateLimit-Reset" => rate_limited.time_remaining,
    "RateLimit-Remaining" => (rate_limited.max_requests - rate_limited.current_requests)
  }

  [429, headers, []]
}
```

## IP Blocking responses

If you're using the IP blocking features of Zen, you can configure the response
we send users when their request is rejected with a Proc that returns a
Rack-compatible response tuple, like this:

``` ruby
Aikido::Zen.blocked_ip_responder = ->(request) {
  # Here, request is an instance of Aikido::Zen::Request, which follows the
  # underlying Rack::Request (or ActionDispatch::Request in Rails) API.
  [403, {"Content-Type" => "application/json"}, ['{"error":"ip_blocked"}']]
}
```

By default, Zen emits a `text/plain` 403 response that tells the user their IP
is not allowed.

## API schema sampling

Zen gathers the requests to your application and infers the request schema,
which is then used for Aikido's API Security and dynamic analysis products.

By default, Zen only inspects up to 10 requests per endpoint every 10 minutes,
to avoid any performance problems.

You can change this number via the `AIKIDO_MAX_API_DISCOVERY_SAMPLES`
environment variable, or via `Aikido::Zen.api_schema_max_samples = {num}`.

You can set this to 0 to disable schema collection entirely.

## JSON encoding/decoding

By default, Zen uses the Ruby standard library's `JSON` module to encode/decode
JSON in our interactions with the Zen API.

If your app uses a different JSON serialization library like Oj, you can
configure Zen to use it like this:

``` ruby
Aikido::Zen.config.json_encoder = Oj.method(:dump)
Aikido::Zen.config.json_decoder = Oj.method(:load)
```
