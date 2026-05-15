Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :vat_validations, only: %i[create show index] do
        get :stats, on: :collection
      end
    end
  end
end
