# frozen_string_literal: true

module Targets
  # Finds active targets that consumed a meaningful number of prompts but
  # returned no or unusually few relevant results during the reporting period.
  class LowYieldQuery
    MIN_PROMPTS = 10
    MAX_VERY_FEW_RESULTS = 2
    VERY_LOW_YIELD = 0.01 # 1%
    LOW_YIELD_WITH_FEW_RESULTS = 0.05 # 5%

    Stat = Struct.new(
      :target,
      :prompts_count,
      :relevant_results_count,
      :yield_percentage,
      keyword_init: true
    )

    RESULT_DOMAIN_SQL = <<~SQL.squish.freeze
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          LOWER(
            COALESCE(
              NULLIF(BTRIM(results.target_domain), ''),
              SUBSTRING(LOWER(results.url) FROM 'https?://([^/]+)')
            )
          ),
          '^https?://', ''
        ),
        '/+$', ''
      )
    SQL

    def self.call(since: 30.days.ago, limit: 5)
      new(since:, limit:).call
    end

    def initialize(since:, limit:)
      @since = since
      @limit = limit
    end

    def call
      prompts_by_target = fetch_prompts_by_target
      candidate_ids = select_candidate_ids(prompts_by_target)
      return [] if candidate_ids.empty?

      relevant_results = fetch_relevant_results_by_domain

      stats = Target.active.where(id: candidate_ids).filter_map do |target|
        build_stat_for_target(target, prompts_by_target, relevant_results)
      end

      sort_and_limit_stats(stats)
    end

    private

    def fetch_prompts_by_target
      Prompt.where(created_at: @since..Time.current)
            .where.not(target_id: nil)
            .group(:target_id)
            .count
    end

    def select_candidate_ids(prompts_by_target)
      prompts_by_target.filter_map do |target_id, count|
        target_id if count >= MIN_PROMPTS
      end
    end

    def fetch_relevant_results_by_domain
      Result.where(created_at: @since..Time.current)
            .where("results.relevance_score > 0")
            .group(Arel.sql(RESULT_DOMAIN_SQL))
            .count
    end

    def build_stat_for_target(target, prompts_by_target, relevant_results)
      return nil if target.domain.blank?

      prompts_count = prompts_by_target.fetch(target.id)
      domain = normalize_domain(target.domain)
      relevant_count = relevant_results.fetch(domain, 0)
      yield_ratio = relevant_count.to_f / prompts_count

      return nil unless low_yield?(relevant_count, yield_ratio)

      Stat.new(
        target:,
        prompts_count:,
        relevant_results_count: relevant_count,
        yield_percentage: (yield_ratio * 100).round(2)
      )
    end

    def sort_and_limit_stats(stats)
      stats.sort_by do |stat|
        [stat.relevant_results_count, stat.yield_percentage, -stat.prompts_count]
      end.first(@limit)
    end

    def normalize_domain(value)
      value.to_s.strip.downcase.sub(%r{\Ahttps?://}i, "").sub(%r{/+\z}, "")
    end

    def low_yield?(relevant_count, yield_ratio)
      relevant_count.zero? ||
        yield_ratio <= VERY_LOW_YIELD ||
        (relevant_count <= MAX_VERY_FEW_RESULTS && yield_ratio <= LOW_YIELD_WITH_FEW_RESULTS)
    end
  end
end
