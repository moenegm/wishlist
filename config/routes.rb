Rails.application.routes.draw do
  resources :wlists do
    patch :toggle_visibility, on: :member
  end
  resources :wishes, except: :index do
    patch :fulfillment, on: :member, action: :update_fulfillment
  end
  resources :follows, only: %i[create destroy]
  resources :likes, only: %i[create destroy]
  resources :comments, only: %i[create destroy]
  resources :notifications, only: :index
  devise_for :users, controllers: { registrations: 'users/registrations' }

  resources :users, only: :show

  root to: "home#index" 
  # Defines the root path route ("/")
  # root "articles#index"
end
