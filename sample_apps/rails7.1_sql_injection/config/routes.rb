Rails.application.routes.draw do
  # Defines routes for the cats resource.
  resources :cats do
    # collection route for counting all cats
    get :count, on: :collection
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  get "benchmark", controller: "benchmark", action: "index"
  get "benchmark_with_user", controller: "benchmark", action: "with_user"

  # Defines the root path route ("/")
  # root "posts#index"
end
