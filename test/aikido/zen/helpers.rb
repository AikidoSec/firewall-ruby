# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::HelpersTests < ActiveSupport::TestCase
  Helpers = Aikido::Zen::Helpers

  test "test normalize path" do
    assert_nil Helpers.normalize_path(nil)
    assert_equal "", Helpers.normalize_path("")
    assert_equal "/", Helpers.normalize_path("/")
    assert_equal "/admin/portal", Helpers.normalize_path("/admin/portal")
    assert_equal "/admin/portal", Helpers.normalize_path("//admin/portal")
    assert_equal "/admin/portal", Helpers.normalize_path("/admin//portal")
    assert_equal "/admin/portal", Helpers.normalize_path("//admin//portal")
    assert_equal "/admin/portal", Helpers.normalize_path("/admin/portal/")
    assert_equal "/admin/portal", Helpers.normalize_path("//admin/portal/")
    assert_equal "/admin/portal", Helpers.normalize_path("/admin//portal/")
    assert_equal "/admin/portal", Helpers.normalize_path("//admin//portal/")
  end
end
