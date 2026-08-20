# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"

class Aikido::Zen::ContextExtractionNormalizationTest < ActiveSupport::TestCase
  setup do
    Aikido::Zen.config.request_builder = Aikido::Zen::Context::RACK_REQUEST_BUILDER
    Aikido::Zen.config.harden = false
  end

  def build_context_for(path, env = {})
    env = Rack::MockRequest.env_for(path, env)
    Aikido::Zen::Context.from_rack_env(env)
  end

  def values(context)
    context.payloads.map { |p| p.value.to_s }
  end

  def present?(context, needle)
    values(context).any? { |v| v.include?(needle) }
  end

  SQLI = "users WHERE id = 1 OR 1=1"

  test "object keys are emitted as scannable payloads" do
    context = build_context_for("/path", {
      method: "POST",
      params: {SQLI => "1"}
    })

    assert present?(context, SQLI), "expected the object key to be extracted as a payload"
  end

  test "URL-encoded values are decoded and emitted as payloads" do
    context = build_context_for("/path", {"HTTP_X_CUSTOM" => Rack::Utils.escape(SQLI)})

    assert present?(context, SQLI), "expected the URL-decoded value to be extracted as a payload"
  end

  test "JWT claims are decoded and emitted as payloads" do
    header = Base64.urlsafe_encode64('{"alg":"HS256","typ":"JWT"}').delete("=")
    body = Base64.urlsafe_encode64(JSON.dump({"sub" => SQLI, "role" => "../../etc/passwd"})).delete("=")
    jwt = "#{header}.#{body}.signaturesignature"

    context = build_context_for("/path", {"HTTP_AUTHORIZATION" => "Bearer #{jwt}"})

    assert present?(context, SQLI), "expected the decoded JWT 'sub' claim to be extracted"
    assert present?(context, "../../etc/passwd"), "expected the decoded JWT 'role' claim to be extracted"
  end

  test "non-JWT strings do not produce spurious payloads" do
    context = build_context_for("/path?q=hello")

    refute values(context).any? { |v| v.include?("\u0000") }
  end
end
