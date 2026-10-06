# frozen_string_literal: true

module SearchEngines
  module Searxng
    class RawResultsCollector < BaseRawResultsCollector
      private

      # [Api::TorClient, Api::PublicInstancesClient]
      def client_classes = [Api::TorClient]
    end
  end
end
