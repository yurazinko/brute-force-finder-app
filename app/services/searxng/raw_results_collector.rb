# frozen_string_literal: true

module Searxng
  class RawResultsCollector
    def self.call(query, options = {}) = new(query, options).collect

    def initialize(query, options = {})
      @query = query
      @options = options
      @combined_data = []
      @failed_engines = []
    end

    def collect
      process_client(Api::TorClient)
      # process_client(Api::PublicInstancesClient)

      @combined_data.uniq! { |result| result["url"] }

      {
        success: @combined_data.any?,
        data: @combined_data,
        failed_engines: @failed_engines.uniq
      }
    end

    private

    def process_client(client_class)
      result = client_class.search(@query, @options)
      return unless result[:success]

      @combined_data.concat(result[:data]) if result[:data].is_a?(Array)
      @failed_engines.concat(result[:failed_engines]) if result[:failed_engines].is_a?(Array)
    end
  end
end
