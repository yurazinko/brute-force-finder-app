# frozen_string_literal: true

module SearchEngines
  module Degoog
    class RawResultsCollector < BaseRawResultsCollector
      private

      def client_classes = [Api::DefaultClient]
    end
  end
end
