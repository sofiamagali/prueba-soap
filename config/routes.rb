Rails.application.routes.draw do
  if Rails.env.development?
    require "sidekiq/web"

    mount Sidekiq::Web => "/sidekiq"
  end

  namespace :api do
    namespace :v1 do
      resources :vat_validations, only: %i[create show index] do
        get :stats, on: :collection
      end
    end
  end
end
