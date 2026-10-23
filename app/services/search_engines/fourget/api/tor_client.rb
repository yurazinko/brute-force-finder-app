# frozen_string_literal: true

module SearchEngines
  module Fourget
    module Api
      class TorClient < BaseClient
        private

        def logger_tag = "FourGet::Api::TorClient"

        def pool_redis_key = "fourget:pool"

        def pool_env_var = "FOURGET_URLS"

        def pool_default_urls = "http://fourget:80"

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
