# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::ConfigTest < Minitest::Test
  setup do
    @config = Aikido::Agent::Config.new
  end

  test "default values" do
    assert_nil @config.api_token
    assert_equal URI("https://guard.aikido.dev"), @config.api_base_url
    assert_equal 10, @config.api_timeouts[:open_timeout]
    assert_equal 10, @config.api_timeouts[:read_timeout]
    assert_equal 10, @config.api_timeouts[:write_timeout]
  end

  test "can overwrite the api_base_url" do
    @config.api_base_url = "https://test.aikido.dev"

    assert_equal URI("https://test.aikido.dev"), @config.api_base_url
  end

  test "can set granular timeouts" do
    @config.api_timeouts = {open_timeout: 1, read_timeout: 2, write_timeout: 3}

    assert_equal 1, @config.api_timeouts[:open_timeout]
    assert_equal 2, @config.api_timeouts[:read_timeout]
    assert_equal 3, @config.api_timeouts[:write_timeout]
  end

  test "can overwrite only some timeouts" do
    @config.api_timeouts = {open_timeout: 5}

    assert_equal 5, @config.api_timeouts[:open_timeout]
    assert_equal 10, @config.api_timeouts[:read_timeout]
    assert_equal 10, @config.api_timeouts[:write_timeout]
  end

  test "can set all timeouts to a single value" do
    @config.api_timeouts = 5

    assert_equal 5, @config.api_timeouts[:open_timeout]
    assert_equal 5, @config.api_timeouts[:read_timeout]
    assert_equal 5, @config.api_timeouts[:write_timeout]
  end

  test "can set the token" do
    @config.api_token = "S3CR3T"

    assert_equal "S3CR3T", @config.api_token
  end

  test "can set the token from an ENV variable" do
    with_env "AIKIDO_TOKEN" => "S3CR3T" do
      config = Aikido::Agent::Config.new
      assert_equal "S3CR3T", config.api_token
    end
  end

  test "can override the default base URL with an ENV variable" do
    with_env "AIKIDO_BASE_URL" => "https://test.aikido.dev" do
      config = Aikido::Agent::Config.new
      assert_equal URI("https://test.aikido.dev"), config.api_base_url
    end
  end

  test "provides a pluggable way of parsing JSON" do
    assert_equal ["foo", "bar"], @config.json_decoder.call(%(["foo","bar"]))

    @config.json_decoder = ->(string) { string.reverse }
    assert_equal "raboof", @config.json_decoder.call("foobar")
  end

  test "provides a pluggable way of encoding JSON" do
    assert_equal %({"foo":"bar"}), @config.json_encoder.call("foo" => "bar")

    @config.json_encoder = ->(obj) { obj.class.to_s }
    assert_equal "Array", @config.json_encoder.call([1, 2])
  end

  def with_env(data = {})
    env = ENV.to_h
    ENV.update(data)
    yield
  ensure
    ENV.replace(env)
  end
end
