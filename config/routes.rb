Rails.application.routes.draw do
  resources :wlists
  resources :wishes
  devise_for :users, controllers: { registrations: 'users/registrations' }

  resources :users, only: :show

  root to: "home#index" 
  # Defines the root path route ("/")
  # root "articles#index"
end
