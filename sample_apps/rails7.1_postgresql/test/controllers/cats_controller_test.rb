require "test_helper"

class CatsControllerTest < ActionDispatch::IntegrationTest
  test "should show cat normally" do
    get cat_url(cats(:feline_dion))
    assert_response :success
  end

  test "show should not allow SQL injection" do
    assert_raises Aikido::Firewall::SQLInjectionError do
      get cat_url("1' OR ''='")
    end
  end
end
