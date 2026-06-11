# frozen_string_literal: true

class SearchActivator
  def self.call(search, target_ids)
    new(search, target_ids).call
  end

  def initialize(search, target_ids)
    @search = search
    @target_ids = target_ids
    @now = Time.current
  end

  def call
    return false if @target_ids.blank? || targets_data.blank?

    Prompt.upsert_all(
      query_records,
      unique_by: %i[target_id full_query_text],
      update_only: %i[search_id status]
    )

    @search.update!(status: "pending")
    true
  rescue StandardError => e
    Rails.logger.error("[SearchActivator] Critical failure during activation for Search##{@search.id}: #{e.message}")
    false
  end

  private

  def targets_data
    @targets_data ||= Target.active.where(id: @target_ids).pluck(:id, :domain)
  end

  def query_records
    @query_records ||= targets_data.map do |target_id, domain|
      {
        search_id: @search.id,
        target_id: target_id,
        full_query_text: "site:#{domain} #{@search.query_conditions}",
        status: "pending",
        created_at: @now,
        updated_at: @now
      }
    end
  end
end
