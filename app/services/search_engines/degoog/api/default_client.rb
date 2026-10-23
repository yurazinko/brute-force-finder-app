# frozen_string_literal: true

module SearchEngines
  module Degoog
    module Api
      class DefaultClient < BaseClient
        private

        def logger_tag = "Degoog::Api::Client"

        def pool_redis_key = "degoog:pool"

        def pool_env_var = "DEGOOG_URLS"

        def pool_default_urls = "http://degoog:4444"
      end
    end
  end
end
