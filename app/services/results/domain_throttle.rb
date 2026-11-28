# frozen_string_literal: true

module Results
  class DomainThrottle
    DEFAULT_TTL = 3.seconds

    def self.acquire?(domain, expires_in: DEFAULT_TTL)
      normalized_domain = domain.to_s.downcase.strip
      raise ArgumentError, "Domain is required" if normalized_domain.blank?

      ttl = expires_in.to_i
      raise ArgumentError, "Throttle TTL must be positive" unless ttl.positive?

      result = Sidekiq.redis do |redis|
        redis.set("domain_throttle:#{normalized_domain}", "1", nx: true, ex: ttl)
      end

      result == "OK"
    end
  end
end
