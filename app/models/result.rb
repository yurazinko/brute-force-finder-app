# frozen_string_literal: true

# == Schema Information
#
# Table name: results
#
#  id                  :bigint           not null, primary key
#  acknowledged        :boolean          default(FALSE), not null
#  content             :text
#  engine              :string
#  matched_keywords    :jsonb            not null
#  relevance_score     :integer          default(0), not null
#  status              :string           default("unread"), not null
#  target_domain       :string
#  target_pattern      :string
#  title               :string
#  url                 :string           not null
#  url_hash            :string           not null
#  verification_status :string           default("pending"), not null
#  viewed_at           :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  search_id           :bigint           not null
#  target_id           :bigint
#
# Indexes
#
#  idx_results_analytics                           (search_id,status,acknowledged)
#  idx_results_content_trgm                        (content gin_trgm_ops) USING gin
#  idx_results_title_trgm                          (title gin_trgm_ops) USING gin
#  idx_results_url_trgm                            (url gin_trgm_ops) USING gin
#  index_results_on_created_at                     (created_at)
#  index_results_on_relevance_score                (relevance_score)
#  index_results_on_search_id                      (search_id)
#  index_results_on_search_id_and_relevance_score  (search_id,relevance_score)
#  index_results_on_search_id_and_status           (search_id,status)
#  index_results_on_search_id_and_target_id        (search_id,target_id)
#  index_results_on_search_id_and_url_hash         (search_id,url_hash) UNIQUE
#  index_results_on_search_status_ack_relevance    (search_id,status,acknowledged,relevance_score)
#  index_results_on_target_domain                  (target_domain)
#  index_results_on_target_id                      (target_id)
#  index_results_on_url_hash                       (url_hash)
#  index_results_on_verification_status            (verification_status)
#
# Foreign Keys
#
#  fk_rails_...  (search_id => searches.id)
#  fk_rails_...  (target_id => targets.id)
#
class Result < ApplicationRecord
  belongs_to :search
  belongs_to :target, optional: true

  after_update :broadcast_acknowledged, if: :saved_change_to_status?

  validates :status, inclusion: { in: %w[unread watched garbage interesting] }

  scope :without_garbage, -> { where.not(status: "garbage") }
  scope :by_status, ->(status) { where(status: status) }
  scope :search_by_keyword, lambda { |query|
    return all if query.blank? || query.strip.length < 3

    sanitized_query = "%#{sanitize_sql_like(query.strip)}%"

    where(
      "results.title ILIKE :q OR results.content ILIKE :q OR results.url ILIKE :q",
      q: sanitized_query
    )
  }

  scope :by_time_frame, lambda { |frame|
    case frame&.to_s
    when "day"   then where(created_at: 1.day.ago.beginning_of_day..)
    when "week"  then where(created_at: 1.week.ago.beginning_of_day..)
    when "month" then where(created_at: 1.month.ago.beginning_of_day..)
    when "year"  then where(created_at: 1.year.ago.beginning_of_day..)
    else all
    end
  }

  def self.top_domains_efficiency(since: 30.days.ago, limit: 5)
    domain_sql = "SUBSTRING(LOWER(results.url) FROM 'https?://([^/]+)')"

    where(created_at: since..Time.current)
      .where("results.relevance_score > 0")
      .where("results.url ~* '^https?://'")
      .group(Arel.sql(domain_sql))
      .order(Arel.sql("SUM(results.relevance_score) DESC, COUNT(*) DESC, AVG(results.relevance_score) DESC"))
      .limit(limit)
      .pluck(
        Arel.sql(domain_sql),
        Arel.sql("COUNT(*)"),
        Arel.sql("SUM(results.relevance_score)"),
        Arel.sql("AVG(results.relevance_score)")
      )
      .map { |row| map_efficiency_row(row) }
  end

  def self.map_efficiency_row(row)
    {
      domain: row[0],
      relevant_results_count: row[1].to_i,
      total_relevance_score: row[2].to_i,
      average_relevance_score: row[3].to_f.round(1)
    }
  end

  private_class_method :map_efficiency_row

  private

  def broadcast_acknowledged
    return if status == "unread"

    Result.where(url_hash: url_hash).update_all(acknowledged: true, updated_at: Time.current)
  end
end
