# frozen_string_literal: true

module Targets
  class LowYieldQuery
    Stat = Struct.new(
      :target,
      :prompts_count,
      :relevant_results_count,
      :yield_percentage,
      keyword_init: true
    )

    def self.call(since: 30.days.ago, limit: 5)
      new(since:, limit:).call
    end

    def initialize(since:, limit:)
      @since = since
      @limit = limit
    end

    def call # rubocop:disable Metrics/MethodLength
      sql = <<~SQL.squish
        SELECT
          targets.*,
          (
            SELECT COUNT(prompts.id)
            FROM prompts
            WHERE prompts.target_id = targets.id
              AND prompts.created_at BETWEEN :since AND :now
          ) AS prompts_count
        FROM targets
        WHERE targets.is_active = TRUE
          AND EXISTS (
            SELECT 1 FROM prompts
            WHERE prompts.target_id = targets.id
              AND prompts.created_at BETWEEN :since AND :now
          )
          AND NOT EXISTS (
            SELECT 1 FROM results
            WHERE results.target_id = targets.id
              AND results.created_at BETWEEN :since AND :now
          )
        ORDER BY prompts_count DESC
        LIMIT :limit
      SQL

      records = Target.find_by_sql([sql, { since: @since, now: Time.current, limit: @limit }])

      records.map do |target|
        prompts_count = target.attributes["prompts_count"].to_i
        Stat.new(
          target: target,
          prompts_count: prompts_count,
          relevant_results_count: 0,
          yield_percentage: 0.0
        )
      end
    end
  end
end
