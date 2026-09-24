# frozen_string_literal: true

module Targets
  class ResultCountsQuery
    def self.call(targets)
      new(targets).call
    end

    def initialize(targets)
      @targets = targets.select { |target| target.domain.present? }
    end

    def call
      return {} if @targets.empty?

      fetch_counts_from_db
    end

    private

    def fetch_counts_from_db
      row = Result.connection.select_one(build_sql_query)

      @targets.each_with_index.to_h do |target, index|
        [target.id, row.fetch("count_#{index}", 0).to_i]
      end
    end

    def build_sql_query
      select_statements = @targets.each_with_index.map do |target, index|
        pattern = "%#{ApplicationRecord.sanitize_sql_like(target.domain)}%"
        quoted_pattern = Result.connection.quote(pattern)
        "COUNT(*) FILTER (WHERE url LIKE #{quoted_pattern}) AS count_#{index}"
      end.join(", ")

      "SELECT #{select_statements} FROM results"
    end
  end
end
