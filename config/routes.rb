Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "quotes#index"

  resources :quotes, only: %i[index new create show] do
    collection do
      post :demo
    end

    member do
      post :approve
      get :export
      get :source
    end

    resource :buyer_questions, only: :show do
      get :download
    end

    resources :quote_lines, only: :update
  end
end
