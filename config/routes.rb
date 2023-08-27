Rails.application.routes.draw do
  resources :wishes
  devise_for :users, controllers: { registrations: 'users/registrations' }

  resources :users

  root to: "home#index" 
  # Defines the root path route ("/")
  # root "articles#index"
end
