# frozen_string_literal: true

module SearchEngines
  module Yacy
    module Api
      class PeerClient < BaseClient
        YACY_POOL_KEY = "yacy:peers_pool"

        private

        def logger_tag = "Yacy::Api::PeerClient"

        def initialize_pool
          return if redis_key_exists?(YACY_POOL_KEY)

          peers = ENV.fetch("YACY_PEER_URLS", "http://localhost:8090").split(",")
          @redis.rpush(YACY_POOL_KEY, peers.shuffle) if peers.any?
        end

        def next_available_instance
          @redis.rpoplpush(YACY_POOL_KEY, YACY_POOL_KEY)
        end
      end
    end
  end
end
