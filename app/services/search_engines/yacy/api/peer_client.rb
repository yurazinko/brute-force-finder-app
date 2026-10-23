# frozen_string_literal: true

module SearchEngines
  module Yacy
    module Api
      class PeerClient < BaseClient
        private

        def logger_tag = "Yacy::Api::PeerClient"

        def pool_redis_key = "yacy:peers_pool"

        def pool_env_var = "YACY_PEER_URLS"

        def pool_default_urls = "http://localhost:8090"
      end
    end
  end
end
