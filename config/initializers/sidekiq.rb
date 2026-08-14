# frozen_string_literal: true

require Rails.root.join("lib/rls/context")
require Rails.root.join("lib/rls/sidekiq/server_middleware")

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }

  config.server_middleware do |chain|
    chain.add Rls::Sidekiq::ServerMiddleware
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
end
