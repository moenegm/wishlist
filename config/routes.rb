Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      post "session", to: "sessions#create"
      delete "session", to: "sessions#destroy"
      post "register", to: "sessions#register"
      post "password_recovery", to: "sessions#recover"
      get "me", to: "me#show"
      patch "me", to: "me#update"
      patch "me/credentials", to: "me#credentials"
      delete "me", to: "me#destroy"
      post "me/avatar", to: "me#avatar"
      resources :wlists, only: %i[index show create update destroy]
      resources :wishes, only: %i[show create update destroy]
      resources :people, only: %i[index show] do
        post :follow, on: :member
        delete :follow, on: :member, action: :unfollow
      end
      post "like", to: "interactions#like"
      delete "like", to: "interactions#unlike"
      get "comments", to: "interactions#comments"
      post "comments", to: "interactions#comment"
      delete "comments/:id", to: "interactions#destroy_comment"
      get "notifications", to: "notifications#index"
      patch "notifications/read", to: "notifications#read"
    end
  end

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
