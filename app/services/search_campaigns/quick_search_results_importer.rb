# frozen_string_literal: true

module SearchCampaigns
  class QuickSearchResultsImporter
    IMPORTABLE_STATUSES = %w[unread watched interesting garbage].freeze

    def initialize(search:, token:)
      @search = search
      @token = token
    end

    def call
      quick_search = QuickSearch::Store.fetch(token)
      return unless importable_quick_search?(quick_search)

      rows = QuickSearch::Store.results(token).filter_map { |attributes| import_attributes(attributes) }
      return 0 if rows.empty?

      inserted = search.results.insert_all(
        rows,
        unique_by: :index_results_on_search_id_and_url_hash,
        returning: %w[id]
      )

      inserted.rows.size
    end

    private

    attr_reader :search, :token

    def importable_quick_search?(quick_search)
      return false unless quick_search && quick_search["status"] == "completed"

      owner_id = quick_search["user_id"]
      owner_id.blank? || owner_id.to_s == search.user_id.to_s
    end

    def import_attributes(raw_attributes)
      attributes = raw_attributes.stringify_keys
      return if attributes["url"].blank? || attributes["url_hash"].blank?

      build_row(attributes)
    end

    def build_row(attributes)
      now = Time.current

      attributes.slice("url", "url_hash", "title", "content", "engine").symbolize_keys.merge(
        status: normalize_status(attributes["status"]),
        acknowledged: ActiveModel::Type::Boolean.new.cast(attributes["acknowledged"]),
        relevance_score: attributes["relevance_score"].to_i,
        matched_keywords: Array(attributes["matched_keywords"]),
        verification_status: attributes["verification_status"].presence || "pending",
        created_at: parse_created_at(attributes["created_at"]),
        updated_at: now,
        search_id: search.id
      )
    end

    def normalize_status(raw_status)
      status = raw_status.to_s
      IMPORTABLE_STATUSES.include?(status) ? status : "unread"
    end

    def parse_created_at(value)
      return Time.current if value.blank?

      Time.zone.parse(value.to_s) || Time.current
    rescue ArgumentError, TypeError
      Time.current
    end
  end
end
