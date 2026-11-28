# frozen_string_literal: true

require "rack/attack"

# Browser-driven system specs sign in repeatedly from the same loopback IP.
# Applying production throttles here makes otherwise independent tests fail
# after the tenth login (and can leave counters in Redis between RSpec runs).
# Rack::Attack remains fully enabled in development and production.
unless Rails.env.test?
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("RATE_LIMIT_REDIS_URL", ENV.fetch("REDIS_URL", "redis://localhost:6379/3")),
    namespace: "rack-attack"
  )

  login_request = lambda do |request|
    request.post? && request.path == "/users/sign_in"
  end

  Rack::Attack.throttle("logins/ip", limit: 10, period: 10.minutes) do |request|
    request.ip if login_request.call(request)
  end

  Rack::Attack.throttle("logins/username", limit: 6, period: 10.minutes) do |request|
    next unless login_request.call(request)

    request.params.dig("user", "username").to_s.downcase.presence
  end

  Rack::Attack.throttle("registrations/ip", limit: 2, period: 1.hour) do |request|
    request.ip if request.post? && request.path == "/users"
  end

  Rack::Attack.throttled_responder = lambda do |_request|
    [429, { "Content-Type" => "text/plain", "Retry-After" => "600", "Cache-Control" => "no-store" },
     ["Too many requests. Try again later."]]
  end
end
