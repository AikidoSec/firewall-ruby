# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::APICacheTest < ActiveSupport::TestCase
  def build_cache
    Aikido::Zen::APICache.new
  end

  test "runtime_config_generation starts at 0" do
    assert_equal 0, build_cache.runtime_config_generation
  end

  test "#runtime_config= increments runtime_config_generation" do
    cache = build_cache
    cache.runtime_config = {"configUpdatedAt" => 1}

    assert_equal 1, cache.runtime_config_generation
  end

  test "#runtime_config= does not increment runtime_config_generation when the value is unchanged" do
    cache = build_cache
    cache.runtime_config = {"configUpdatedAt" => 1}

    cache.runtime_config = {"configUpdatedAt" => 1}

    assert_equal 1, cache.runtime_config_generation
  end

  test "#config_if_changed returns the value and generation when the known generation is nil" do
    cache = build_cache
    cache.runtime_config = {"configUpdatedAt" => 1}

    assert_equal [cache.runtime_config, cache.runtime_config_generation], cache.config_if_changed(nil)
  end

  test "#config_if_changed returns nil when the known generation matches the current one" do
    cache = build_cache
    cache.runtime_config = {"configUpdatedAt" => 1}

    assert_nil cache.config_if_changed(cache.runtime_config_generation)
  end

  test "#config_if_changed returns the value and generation again once it changes" do
    cache = build_cache
    cache.runtime_config = {"configUpdatedAt" => 1}
    stale_generation = cache.runtime_config_generation

    cache.runtime_config = {"configUpdatedAt" => 2}

    assert_equal [{"configUpdatedAt" => 2}, cache.runtime_config_generation], cache.config_if_changed(stale_generation)
  end

  test "runtime_firewall_lists_generation starts at 0" do
    assert_equal 0, build_cache.runtime_firewall_lists_generation
  end

  test "#runtime_firewall_lists= increments runtime_firewall_lists_generation" do
    cache = build_cache
    cache.runtime_firewall_lists = {"blockedIPAddresses" => []}

    assert_equal 1, cache.runtime_firewall_lists_generation
  end

  test "#runtime_firewall_lists= does not increment runtime_firewall_lists_generation when the value is unchanged" do
    cache = build_cache
    cache.runtime_firewall_lists = {"blockedIPAddresses" => []}

    cache.runtime_firewall_lists = {"blockedIPAddresses" => []}

    assert_equal 1, cache.runtime_firewall_lists_generation
  end

  test "#firewall_lists_if_changed returns the value and generation when the known generation is nil" do
    cache = build_cache
    cache.runtime_firewall_lists = {"blockedIPAddresses" => []}

    assert_equal [cache.runtime_firewall_lists, cache.runtime_firewall_lists_generation],
      cache.firewall_lists_if_changed(nil)
  end

  test "#firewall_lists_if_changed returns nil when the known generation matches the current one" do
    cache = build_cache
    cache.runtime_firewall_lists = {"blockedIPAddresses" => []}

    assert_nil cache.firewall_lists_if_changed(cache.runtime_firewall_lists_generation)
  end

  test "#firewall_lists_if_changed returns the value and generation again once it changes" do
    cache = build_cache
    cache.runtime_firewall_lists = {"blockedIPAddresses" => []}
    stale_generation = cache.runtime_firewall_lists_generation

    cache.runtime_firewall_lists = {"blockedIPAddresses" => ["1.2.3.4"]}

    assert_equal [{"blockedIPAddresses" => ["1.2.3.4"]}, cache.runtime_firewall_lists_generation],
      cache.firewall_lists_if_changed(stale_generation)
  end
end
