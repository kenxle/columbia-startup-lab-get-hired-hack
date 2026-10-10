Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "quotes#index"
  get "buyer-answer", to: "buyer_answer_links#show", as: :buyer_answer_link

  get "product", to: "marketing#product", as: :product
  get "compare", to: "marketing#comparison", as: :comparison

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
      post :preview_email
    end

    resource :final_quote, only: :show do
      get :download
      get :pdf
      post :preview_email
      post :deliver
    end

    resources :quote_lines, only: :update
    resources :local_previews, only: %i[index show] do
      member do
        get :download
        get :attachment
      end
    end
    resources :buyer_answers, only: :create
    resources :buyer_terms, only: :create
    resource :processing, only: :create, controller: "processing_runs"
    resource :pricing, only: %i[show create], controller: "pricing_runs"
  end

  # Tisch: catalog matching agent (client description -> catalog items -> RFQ).
  resources :catalog_matches, only: %i[index create show] do
    member { post :approve }
    collection do
      post :teach
      delete :forget
    end
  end
end
