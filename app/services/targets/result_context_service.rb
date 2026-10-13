# frozen_string_literal: true

module Targets
  class ResultContextService
    attr_reader :result, :search, :default_path, :path_segments, :available_targets, :matched_target

    def self.call(...) = new(...).call

    def initialize(current_user:, result_id:)
      @current_user = current_user
      @result_id = result_id
    end

    def call
      return unless @result_id

      @result = Result.find(@result_id)
      parse_uri_details
      load_search_and_targets
      match_target
      self
    rescue ActiveRecord::RecordNotFound
      raise ActiveRecord::RecordNotFound, "Result not found."
    end

    private

    def parse_uri_details
      uri = URI.parse(@result.url)
      @default_path = uri.path.presence || "/"

      clean_path = @default_path.sub(%r{\A/+}, "").chomp("/")
      @path_segments = clean_path.split("/")
    end

    def load_search_and_targets
      @search = @result.search
      @available_targets = Target.joins(:category)
                                 .where(categories: { user_id: @current_user.id })
                                 .distinct
    end

    def match_target
      @matched_target = @available_targets.find { |t| Results::UrlMatcher.matches?(@result.url, t) }
    end
  end
end
