# frozen_string_literal: true

require "test_helper"

class AttackWaveTest < ActiveSupport::TestCase
  include RailsServerHelpers
  include MockServerHelpers

  test "records the real scanned path when a custom 404 controller rewrites PATH_INFO" do
    client_ip = random_client_ip

    response = rails_get("/wp-config.php", headers: {"X-Forwarded-For" => client_ip})
    assert_equal "404", response.code

    event = poll_until(timeout: 10) do
      received_events(type: "detected_attack_wave").find { |e| e.dig("request", "ipAddress") == client_ip }
    end

    samples = JSON.parse(event.dig("attack", "metadata", "samples"))
    urls = samples.map { |sample| sample["url"] }

    assert_includes urls, "/wp-config.php",
      "expected the attack wave sample to record the original path"
    assert_not_includes urls, "/404",
      "expected the attack wave sample not to record the rewritten path"
  end

  private

  def random_client_ip
    "10.#{rand(1..254)}.#{rand(1..254)}.#{rand(1..254)}"
  end
end
