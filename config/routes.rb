# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  mount Sidekiq::Web => "/sidekiq"

  # Defines the root path route ("/")
  # root "posts#index"
  resources :searches, only: %i[index show new edit update create destroy] do
    member do
      post :activate
    end
  end

  resources :categories

  resource :dashboard, only: [:show]

  resources :targets, only: %i[create destroy edit update]

  resources :results, only: [:update]

  resources :data_transfers, only: [:index] do
    collection do
      post :export
      post :import
    end
  end

  root "searches#index"
end
