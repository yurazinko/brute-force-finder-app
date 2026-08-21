# frozen_string_literal: true

module SearchEngines
  module Yacy
    class RawResultsCollector
      def self.call(query, options = {}) = new(query, options).collect

      def initialize(query, options = {})
        @query = query
        @options = options
        @combined_data = []
        @failed_engines = []
        @errors = []
      end

      def collect
        process_client(Api::PeerClient)

        @combined_data.uniq! { |result| result["url"] }

        {
          success: @combined_data.any?,
          data: @combined_data,
          failed_engines: @failed_engines.uniq,
          error: @combined_data.empty? ? @errors.join(", ").presence : nil
        }
      end

      private

      def process_client(client_class)
        result = client_class.search(@query, @options)

        if result[:success]
          @combined_data.concat(result[:data]) if result[:data].is_a?(Array)
          @failed_engines.concat(result[:failed_engines]) if result[:failed_engines].is_a?(Array)
        elsif result[:error].present?
          @errors << "#{client_class.name}: #{result[:error]}"
        end
      end
    end
  end
end
