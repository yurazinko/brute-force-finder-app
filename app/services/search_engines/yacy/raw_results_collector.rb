# frozen_string_literal: true

module SearchEngines
  module Yacy
    class RawResultsCollector < BaseRawResultsCollector
      private

      def client_classes = [Api::PeerClient]
    end
  end
end
