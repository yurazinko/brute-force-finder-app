# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users
  require "sidekiq/web"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "healthz" => "healthchecks#show", as: :healthz

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  mount Sidekiq::Web => "/sidekiq"

  # Defines the root path route ("/")
  # root "posts#index"
  resources :quick_searches, only: %i[create show], param: :token do
    collection do
      delete :clear
    end

    member do
      get :save_as_campaign
      patch :mark_as_read
    end
  end

  resources :searches, only: %i[index show new edit update create destroy] do
    member do
      post :activate
      patch :toggle_pause
      patch :complete
    end
  end

  resources :categories

  resource :dashboard, only: [:show]

  resources :targets, only: %i[new create destroy edit update]

  resources :target_patterns, only: %i[new create update destroy]

  resources :results, only: %i[index update] do
    member do
      patch :mark_as_read
    end

    collection do
      patch :bulk_update
    end
  end

  get "data_transfers/download", to: "data_export_downloads#show", as: :data_transfers_download

  resources :data_transfers, only: [:index] do
    collection do
      post :export
      post :import
    end
  end

  root "quick_searches#show"
end
