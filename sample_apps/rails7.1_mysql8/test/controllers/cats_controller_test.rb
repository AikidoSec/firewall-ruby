require "test_helper"

class CatsControllerTest < ActionDispatch::IntegrationTest
  test "should show cat normally" do
    get cat_url(cats(:feline_dion))
    assert_response :success
  end
end
