Rails.application.routes.draw do
  # Resource routing :
  get "/file" => "file#show", :as => :file_show

  get "up" => "rails/health#show", :as => :rails_health_check

end
