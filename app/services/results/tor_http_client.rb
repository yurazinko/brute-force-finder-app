# frozen_string_literal: true

require "httparty"

module Results
  class TorHttpClient
    include HTTParty

    connection_adapter Results::TorSocksConnectionAdapter
  end
end
