# frozen_string_literal: true

module Results
  class BulkUpdateService
    BULK_TARGET_STATUSES = %w[unread watched interesting garbage].freeze

    attr_reader :search, :target_status, :visible_ids, :filter_options

    def initialize(search:, target_status:, visible_ids:, filter_options:)
      @search = search
      @target_status = target_status.to_s
      @visible_ids = visible_ids
      @filter_options = filter_options
    end

    def call
      return 0 unless valid_target_status? && visible_ids.any?

      eligible_scope = Results::Query.call(search.results, filter_options, search: search)

      eligible_scope.where(id: visible_ids).update_all(
        status: target_status,
        acknowledged: target_status != "unread",
        updated_at: Time.current
      )
    end

    private

    def valid_target_status?
      BULK_TARGET_STATUSES.include?(target_status)
    end
  end
end
