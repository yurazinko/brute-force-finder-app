# frozen_string_literal: true

require "sidekiq/api"

class HealthchecksController < ActionController::API
  def show
    checks = {
      database: database_available?,
      redis: redis_available?,
      sidekiq: sidekiq_available?
    }

    healthy = checks.values.all?
    render json: {
      status: healthy ? "ok" : "unavailable",
      checks: checks.transform_values { |ok| ok ? "ok" : "failed" }
    }, status: healthy ? :ok : :service_unavailable
  end

  private

  def database_available?
    ActiveRecord::Base.connection.select_value("SELECT 1").to_i == 1
  rescue StandardError => e
    Rails.logger.error("[Healthchecks] Database check failed: #{e.class}: #{e.message}")
    false
  end

  def redis_available?
    Sidekiq.redis { |redis| redis.ping == "PONG" }
  rescue StandardError => e
    Rails.logger.error("[Healthchecks] Redis check failed: #{e.class}: #{e.message}")
    false
  end

  def sidekiq_available?
    Sidekiq::ProcessSet.new.any?
  rescue StandardError => e
    Rails.logger.error("[Healthchecks] Sidekiq check failed: #{e.class}: #{e.message}")
    false
  end
end
