Rails.application.routes.draw do
  resources :wlists
  resources :wishes
  resources :people, only: :index
  resources :follows, only: %i[create destroy]
  devise_for :users, controllers: { registrations: 'users/registrations' }

  resources :users, only: :show

  root to: "home#index" 
  # Defines the root path route ("/")
  # root "articles#index"
end
