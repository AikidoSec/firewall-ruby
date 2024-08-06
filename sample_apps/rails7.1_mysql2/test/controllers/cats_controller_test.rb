require "test_helper"

class CatsControllerTest < ActionDispatch::IntegrationTest
  # Disable the transaction around tests, otherwise the exception raised when
  # finding breaks due to the injected DELETE statement will rollback the test
  # database changes, making it impossible to detect if the cats were, in fact,
  # deleted.
  self.use_transactional_tests = false

  test "should show cat normally" do
    get cat_url(cats(:feline_dion))
    assert_response :success
  end

  test "show should not allow SQL injection" do
    assert_no_difference("Cat.count") do
      err = assert_raises ActiveRecord::StatementInvalid do
        get cat_url("1'); DELETE FROM cats; --")
      end

      assert_kind_of Aikido::Firewall::SQLInjectionError, err.cause
    end
  end
end
