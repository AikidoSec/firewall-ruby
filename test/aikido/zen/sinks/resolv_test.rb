# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::ResolvTest < ActiveSupport::TestCase
  include SinkAttackHelpers

  setup { @dns = StubbedResolver.new }

  # Ensures we check predictable sources of DNS resolution for testing.
  def with_stubbed_resolver(&block)
    Tempfile.create do |hosts|
      hosts.puts "255.255.255.255 broadcasthost"
      hosts.puts "127.0.0.1 localhost"
      hosts.puts "::1 localhost"
      hosts.close

      resolver = Resolv.new([Resolv::Hosts.new(hosts.path), @dns])
      Resolv.stub_const(:DefaultResolver, resolver, &block)
    end
  end

  class MaintainsBehaviorTest < self
    test "#getaddresses resolves addresses from the hosts file" do
      with_stubbed_resolver do
        addresses = Resolv.getaddresses("localhost")
        assert_includes addresses, "127.0.0.1"
        assert_includes addresses, "::1"
      end
    end

    test "#getaddresses resolves 'internet' addresses" do
      with_stubbed_resolver do
        @dns.define("example.com" => ["1.1.1.1", "2.2.2.2"])

        addresses = Resolv.getaddresses("example.com")
        assert_includes addresses, "1.1.1.1"
        assert_includes addresses, "2.2.2.2"

        assert_empty Resolv.getaddresses("not.example.com")
      end
    end

    test "#getaddress resolves addresses from the hosts file" do
      with_stubbed_resolver do
        assert_equal "::1", Resolv.getaddress("localhost")
      end
    end

    test "#getaddress resolves 'internet' addresses" do
      with_stubbed_resolver do
        @dns.define("example.com" => ["1.1.1.1", "2.2.2.2"])

        assert_equal "1.1.1.1", Resolv.getaddress("example.com")

        assert_raises Resolv::ResolvError do
          Resolv.getaddress("not.example.com")
        end
      end
    end

    test "#each_address yields addresses in turn" do
      with_stubbed_resolver do
        addresses = ["1.1.1.1", "2.2.2.2"]

        @dns.define("example.com" => addresses.dup)

        Resolv.each_address("example.com") do |address|
          assert_equal addresses.shift, address
        end

        assert_empty addresses # to check we actually did iterate over it.
      end
    end
  end

  class BlocksStoredSSRFTest < self
    test "#getaddresses blocks stored SSRF attacks" do
      Aikido::Zen.config.blocking_mode = true

      with_stubbed_resolver do
        @dns.define("im-harmless.com" => ["169.254.169.254"])

        error = assert_attack Aikido::Zen::Attacks::StoredSSRFAttack do
          Resolv.getaddresses("im-harmless.com")
        end

        assert_equal \
          "Stored SSRF: Request to sensitive host «im-harmless.com» (169.254.169.254) detected from unknown source in resolv.lookup", error.message
      end
    end

    test "#getaddress blocks stored SSRF attacks" do
      Aikido::Zen.config.blocking_mode = true

      with_stubbed_resolver do
        @dns.define("im-harmless.com" => ["169.254.169.254"])

        error = assert_attack Aikido::Zen::Attacks::StoredSSRFAttack do
          Resolv.getaddress("im-harmless.com")
        end

        assert_equal \
          "Stored SSRF: Request to sensitive host «im-harmless.com» (169.254.169.254) detected from unknown source in resolv.lookup", error.message
      end
    end

    test "#each_address blocks stored SSRF attacks" do
      Aikido::Zen.config.blocking_mode = true

      with_stubbed_resolver do
        @dns.define("im-harmless.com" => ["169.254.169.254"])

        error = assert_attack Aikido::Zen::Attacks::StoredSSRFAttack do
          Resolv.each_address("im-harmless.com") do |address|
            raise "should not get to #{address}"
          end
        end

        assert_equal \
          "Stored SSRF: Request to sensitive host «im-harmless.com» (169.254.169.254) detected from unknown source in resolv.lookup", error.message
      end
    end
  end

  class BlocksSSRFAttacks < self
    setup do
      Aikido::Zen.config.blocking_mode = true
    end

    def build_request_to(uri)
      Aikido::Zen::Scanners::SSRFScanner::Request.new(
        verb: "GET",
        uri: URI(uri),
        headers: {}
      )
    end

    test "#getaddresses blocks SSRF attacks if the context knows of an ongoing request" do
      set_context_from_request_to "/?host=im-harmless.com"

      # This would be set by an HTTP lib's sink
      Aikido::Zen.current_context["ssrf.request"] = build_request_to("https://im-harmless.com/")

      with_stubbed_resolver do
        @dns.define("im-harmless.com" => ["10.0.0.1"])

        error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
          Resolv.getaddresses("im-harmless.com")
        end

        assert_equal \
          "SSRF: Request to user-supplied hostname «im-harmless.com» detected in resolv.lookup (GET https://im-harmless.com/).",
          error.message
      end
    end

    test "#getaddress blocks SSRF attacks if the context knows of an ongoing request" do
      set_context_from_request_to "/?host=im-harmless.com"

      Aikido::Zen.current_context["ssrf.request"] = build_request_to("https://im-harmless.com/")

      with_stubbed_resolver do
        @dns.define("im-harmless.com" => ["10.0.0.1"])

        error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
          Resolv.getaddress("im-harmless.com")
        end

        assert_equal \
          "SSRF: Request to user-supplied hostname «im-harmless.com» detected in resolv.lookup (GET https://im-harmless.com/).",
          error.message
      end
    end

    test "#each_address blocks SSRF attacks if the context knows of an ongoing request" do
      Aikido::Zen.config.blocking_mode = true

      set_context_from_request_to "/?host=im-harmless.com"

      Aikido::Zen.current_context["ssrf.request"] = build_request_to("https://im-harmless.com/")

      with_stubbed_resolver do
        @dns.define("im-harmless.com" => ["10.0.0.1"])

        error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
          Resolv.each_address("im-harmless.com") { |address| raise "unreachable" }
        end

        assert_equal \
          "SSRF: Request to user-supplied hostname «im-harmless.com» detected in resolv.lookup (GET https://im-harmless.com/).",
          error.message
      end
    end
  end

  # Static table so tests don't actually hit a DNS server.
  class StubbedResolver
    def initialize
      @table = Hash.new { |h, k| h[k] = [] }
    end

    def define(table)
      @table.update(table)
    end

    def each_address(name, &block)
      @table[name].each(&block)
    end

    def getaddresses(name)
      @table[name]
    end

    def getaddress(name)
      getaddresses(name).first or raise Resolv::ResolvError
    end
  end
end
