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

    def self.call(since: 30.days.ago, limit: 5, category_ids: nil)
      new(since:, limit:, category_ids:).call
    end

    def initialize(since:, limit:, category_ids:)
      @since = since
      @limit = limit
      @category_ids = category_ids
    end

    def call # rubocop:disable Metrics/MethodLength
      category_condition = @category_ids.present? ? "AND targets.category_id IN (:category_ids)" : ""

      sql = <<~SQL.squish
        SELECT
          targets.*,
          (
            SELECT COUNT(prompts.id)
            FROM prompts
            WHERE prompts.target_id = targets.id
              AND prompts.status <> 'pending'
              AND prompts.created_at >= :since
          ) AS prompts_count
        FROM targets
        WHERE targets.is_active = TRUE
          #{category_condition}
          AND EXISTS (
            SELECT 1 FROM prompts
            WHERE prompts.target_id = targets.id
              AND prompts.status <> 'pending'
              AND prompts.created_at >= :since
          )
          AND NOT EXISTS (
            SELECT 1 FROM results
            WHERE results.target_id = targets.id
              AND results.created_at >= :since
          )
        ORDER BY prompts_count DESC
        LIMIT :limit
      SQL

      params = { since: @since, limit: @limit }
      params[:category_ids] = @category_ids if @category_ids.present?

      records = Target.find_by_sql([sql, params])

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
