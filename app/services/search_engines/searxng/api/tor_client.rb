# frozen_string_literal: true

module SearchEngines
  module Searxng
    module Api
      class TorClient < BaseClient
        private

        def logger_tag = "Searxng::Api::TorClient"

        def pool_redis_key = "searxng:pool"

        def pool_env_var = "SEARXNG_URLS"

        def pool_default_urls = "http://searxng_1:8080"

        def query_options
          random_auth = SecureRandom.hex(8)
          super.merge(
            socks_username: random_auth,
            socks_password: random_auth
          )
        end
      end
    end
  end
end
