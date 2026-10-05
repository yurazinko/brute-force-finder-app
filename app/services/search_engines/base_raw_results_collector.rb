# frozen_string_literal: true

module SearchEngines
  class BaseRawResultsCollector
    def self.call(query, options = {}) = new(query, options).collect

    def initialize(query, options = {})
      @query = query
      @options = options
      @combined_data = []
      @failed_engines = []
      @errors = []
    end

    def collect
      client_classes.each { |client_class| process_client(client_class) }

      @combined_data.uniq! { |result| result["url"] }

      {
        success: @combined_data.any?,
        data: @combined_data,
        failed_engines: @failed_engines.uniq,
        error: @combined_data.empty? ? @errors.join(", ").presence : nil
      }
    end

    private

    def client_classes
      raise NotImplementedError, "#{self.class} must define #client_classes"
    end

    def process_client(client_class)
      result = client_class.search(@query, @options)

      @combined_data.concat(result[:data]) if result[:data].is_a?(Array)

      @failed_engines.concat(result[:failed_engines]) if result[:failed_engines].is_a?(Array)

      return if result[:success]

      @errors << "#{client_class.name}: #{result[:error]}" if result[:error].present?
    end
  end
end
