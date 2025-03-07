require "test_helper"

class FilesControllerTest < ActionDispatch::IntegrationTest
  test "request should success" do
    get "/file?filename=file_controller.rb"
    assert_response :success
  end

  test "request return 404 if the fiel does not exist" do
    get "/file?filename=some-file.txt"
    assert_response :not_found
  end

  test "PathTraversal attacks are detected and blocked" do
    assert_raises Aikido::Zen::PathTraversalError do
      get "/file?filename=../../config/environment.rb"
    end
  end
end
