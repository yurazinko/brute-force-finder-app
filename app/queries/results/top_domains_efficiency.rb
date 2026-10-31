# frozen_string_literal: true

module Results
  class TopDomainsEfficiency
    def self.call(since: 30.days.ago, limit: 5)
      new(since: since, limit: limit).call
    end

    def initialize(since:, limit:)
      @since = since
      @limit = limit
    end

    def call
      Result.joins(:target, :search)
            .where(created_at: @since..Time.current)
            .where(relevance_condition)
            .group("targets.id", "targets.domain")
            .order(Arel.sql("SUM(results.relevance_score) DESC, COUNT(*) DESC, AVG(results.relevance_score) DESC"))
            .limit(@limit)
            .pluck(
              "targets.id",
              "targets.domain",
              Arel.sql("COUNT(*)"),
              Arel.sql("SUM(results.relevance_score)"),
              Arel.sql("AVG(results.relevance_score)")
            )
            .map { |row| map_efficiency_row(row) }
    end

    private

    def relevance_condition
      "(searches.relevance_mode = 'strict' AND results.relevance_score >= 100) " \
        "OR (searches.relevance_mode = 'balanced' AND results.relevance_score > 0)"
    end

    def map_efficiency_row(row)
      {
        id: row[0],
        domain: row[1],
        relevant_results_count: row[2].to_i,
        total_relevance_score: row[3].to_i,
        average_relevance_score: row[4].to_f.round(1)
      }
    end
  end
end
