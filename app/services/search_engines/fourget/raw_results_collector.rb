# frozen_string_literal: true

module SearchEngines
  module Fourget
    class RawResultsCollector < BaseRawResultsCollector
      private

      def client_classes = [Api::TorClient]
    end
  end
end
