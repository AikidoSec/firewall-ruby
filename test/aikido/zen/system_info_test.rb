# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::InfoTest < ActiveSupport::TestCase
  setup do
    @info = Aikido::Zen::SystemInfo.new
  end

  test "by default, attacks do not block requests" do
    assert_equal false, @info.attacks_block_requests?
    assert_equal true, @info.attacks_are_only_reported?
  end

  test "attacks block requests if blocking_mode is turned on in the config" do
    Aikido::Zen.config.blocking_mode = true

    assert_equal true, @info.attacks_block_requests?
    assert_equal false, @info.attacks_are_only_reported?
  end

  test "library_name is firewall-ruby" do
    assert_equal "firewall-ruby", @info.library_name
  end

  test "library_version matches the gem version" do
    assert_equal Aikido::Zen::VERSION, @info.library_version
  end

  test "platform_version returns the current ruby version" do
    assert_equal RUBY_VERSION, @info.platform_version
  end

  test "#session_id is a UUID that is stable per instance and unique across instances" do
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, @info.session_id)
    assert_equal @info.session_id, @info.session_id
    refute_equal @info.session_id, Aikido::Zen::SystemInfo.new.session_id
  end

  test "#hostname is nil when the lookup fails" do
    Socket.stub :gethostname, -> { raise Errno::ENOENT } do
      assert_nil Aikido::Zen::SystemInfo.new.hostname
    end
  end

  test "#hostname is nil when the lookup returns an empty name" do
    Socket.stub :gethostname, "" do
      assert_nil Aikido::Zen::SystemInfo.new.hostname
    end
  end

  test "#ip_address returns the first non-loopback address reported" do
    addresses = [
      Addrinfo.ip("::1"),
      Addrinfo.ip("127.0.0.1"),
      Addrinfo.ip("192.168.0.1"),
      Addrinfo.ip("10.10.0.1")
    ]

    Socket.stub(:ip_address_list, addresses) do
      assert_equal "192.168.0.1", @info.ip_address
    end
  end

  test "#ip_address prefers IPv4 over IPv6" do
    addresses = [
      Addrinfo.ip("2a02:a018:14b:fe00:1823:e142:94cc:f088"),
      Addrinfo.ip("192.168.0.1")
    ]

    Socket.stub(:ip_address_list, addresses) do
      assert_equal "192.168.0.1", @info.ip_address
    end
  end

  test "#ip_address falls back on IPv6 if no non-lo IPv4 addresses are given" do
    addresses = [
      Addrinfo.ip("::1"),
      Addrinfo.ip("2a02:a018:14b:fe00:1823:e142:94cc:f088"),
      Addrinfo.ip("127.0.0.1")
    ]

    Socket.stub(:ip_address_list, addresses) do
      assert_equal "2a02:a018:14b:fe00:1823:e142:94cc:f088", @info.ip_address
    end
  end

  test "#ip_address is nil when the lookup fails" do
    Socket.stub :ip_address_list, -> { raise Errno::ENOENT } do
      assert_nil Aikido::Zen::SystemInfo.new.ip_address
    end
  end

  test "#ip_address is nil when the lookup returns no usable address" do
    Socket.stub :ip_address_list, [] do
      assert_nil Aikido::Zen::SystemInfo.new.ip_address
    end
  end

  test "#agent_headers uses 'unknown' for the hostname when it cannot be determined" do
    Socket.stub :gethostname, "" do
      headers = Aikido::Zen::SystemInfo.new.agent_headers

      assert_equal "unknown", headers["X-Agent-Hostname"]
    end
  end

  test "#agent_headers uses 'unknown' for the IP address when it cannot be determined" do
    Socket.stub :ip_address_list, [] do
      headers = Aikido::Zen::SystemInfo.new.agent_headers

      assert_equal "unknown", headers["X-Agent-IP-Address"]
    end
  end

  test "#agent_headers includes all the agent identification headers" do
    assert_equal({
      "X-Agent-Platform" => "ruby",
      "X-Agent-Library" => "firewall-ruby",
      "X-Agent-Version" => Aikido::Zen::VERSION,
      "X-Agent-Hostname" => @info.hostname,
      "X-Agent-IP-Address" => @info.ip_address,
      "X-Agent-Session-Id" => @info.session_id
    }, @info.agent_headers)
  end

  test "#packages maps the list of supported loaded gems into a list of Package instances" do
    test_specs = Gem.loaded_specs.slice("concurrent-ruby", "minitest", "rack")

    Aikido::Zen::Sinks.add("minitest", "test_op", scanners: [NOOP])
    Aikido::Zen::Sinks.add("concurrent-ruby", "test_op", scanners: [NOOP])

    Gem.stub(:loaded_specs, test_specs) do
      expected_packages = [
        Aikido::Zen::Package.new("concurrent-ruby", test_specs["concurrent-ruby"].version),
        Aikido::Zen::Package.new("minitest", test_specs["minitest"].version)
      ]

      assert_equal expected_packages, @info.packages
    end
  end

  test "as_json includes the expected fields" do
    Aikido::Zen::Sinks.add("concurrent-ruby", "test_op", scanners: [NOOP])

    assert_equal @info.attacks_are_only_reported?, @info.as_json["dryMode"]
    assert_equal @info.library_name, @info.as_json["library"]
    assert_equal @info.library_version, @info.as_json["version"]
    assert_equal @info.hostname, @info.as_json["hostname"]
    assert_equal @info.ip_address, @info.as_json["ipAddress"]
    assert_equal @info.os_name, @info.as_json.dig("os", "name")
    assert_equal @info.os_version, @info.as_json.dig("os", "version")
    assert_equal @info.platform_version, @info.as_json.dig("platform", "version")

    # To keep the test scalable, only test one known dependency.
    assert_kind_of Hash, @info.as_json["packages"]
    assert_equal \
      Gem.loaded_specs["concurrent-ruby"].version.to_s,
      @info.as_json.dig("packages", "concurrent-ruby")

    assert_equal "", @info.as_json["nodeEnv"]
    assert_equal false, @info.as_json["preventedPrototypePollution"]

    assert_equal false, @info.as_json["serverless"]
    assert_equal [], @info.as_json["stack"]
    assert_equal({}, @info.as_json["incompatiblePackages"])
  end
end
