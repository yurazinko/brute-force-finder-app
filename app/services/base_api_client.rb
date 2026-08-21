# frozen_string_literal: true

require "httparty"

class BaseApiClient
  include HTTParty

  TIMEOUT = 12
  MAX_RETRIES = 3
  CIRCUIT_BREAKER_TTL = 900

  default_timeout TIMEOUT

  def self.search(query, options = {}) = new(query, options).execute

  def initialize(query, options = {})
    @query = query
    @options = options
    @time_range = options[:time_range]
    @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/1"))
    initialize_pool
  end

  def execute
    return { success: true, data: [] } if @query.blank?

    attempts = 0

    while attempts < max_retries_count
      instance = next_available_instance
      return { success: false, error: "All #{provider_name} instances are currently dead" } if instance.blank?

      result = perform_request(instance)
      res_hash = result.respond_to?(:to_h) ? result.to_h : result

      return res_hash if res_hash.is_a?(Hash) && res_hash[:success]

      attempts += 1
    end

    { success: false, error: "Failed after #{max_retries_count} attempts across multiple instances" }
  end

  private

  def initialize_pool = raise(NotImplementedError)

  def next_available_instance = raise(NotImplementedError)

  def logger_tag = raise(NotImplementedError)

  def provider_name = raise(NotImplementedError)

  def redis_dead_prefix = raise(NotImplementedError)

  def perform_request(_instance) = raise(NotImplementedError)

  def redis_key_exists?(key)
    res = @redis.exists?(key)
    res.is_a?(Integer) ? res.positive? : res
  end

  def triaged_as_dead(instance)
    @redis.setex("#{redis_dead_prefix}#{instance}", CIRCUIT_BREAKER_TTL, "dead")
  end

  def max_retries_count = MAX_RETRIES
end
