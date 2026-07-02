# frozen_string_literal: true

class Result < ApplicationRecord
  belongs_to :search

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

  def self.top_domains_efficiency
    group("SUBSTRING(url FROM 'https?://([^/]+)')")
      .order(count_all: :desc)
      .limit(5)
      .count
      .transform_keys { |k| k.nil? ? "Unknown" : k.to_s }
  end

  private

  def broadcast_acknowledged
    return if status == "unread"

    Result.where(url_hash: url_hash).update_all(acknowledged: true, updated_at: Time.current)
  end
end
