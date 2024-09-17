require "test_helper"

class CatsControllerTest < ActionDispatch::IntegrationTest
  test "should show cat normally" do
    get cat_url(cats(:feline_dion))
    assert_response :success
  end

  test "show should not allow SQL injection" do
    err = assert_raises ActiveRecord::StatementInvalid do
      get cat_url("1' OR ''='")
    end

    assert_kind_of Aikido::Zen::SQLInjectionError, err.cause
  end
end
