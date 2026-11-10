# frozen_string_literal: true

module Results
  class BulkUpdateService
    BULK_TARGET_STATUSES = %w[unread watched interesting garbage].freeze
    BULK_SCOPE_MODES = %w[visible all_matching].freeze

    attr_reader :search, :target_status, :visible_ids, :filter_options, :scope_mode

    def initialize(search:, target_status:, filter_options:, visible_ids: [], scope_mode: "visible")
      @search = search
      @target_status = target_status.to_s
      @visible_ids = Array(visible_ids)
      @filter_options = filter_options
      @scope_mode = scope_mode.to_s.presence || "visible"
    end

    def call
      return 0 unless valid_target_status? && valid_scope_mode?
      return 0 if scope_mode == "visible" && visible_ids.empty?

      # This is the same unpaginated scope that powers the Search tab. It applies
      # the active tab, acknowledgement, keyword/timeframe and relevance filters.
      eligible_scope = Results::Query.call(search.results, filter_options, search: search).except(:order)
      target_scope = scope_mode == "all_matching" ? eligible_scope : eligible_scope.where(id: visible_ids)

      target_scope.update_all(
        status: target_status,
        acknowledged: target_status != "unread",
        updated_at: Time.current
      )
    end

    private

    def valid_target_status?
      BULK_TARGET_STATUSES.include?(target_status)
    end

    def valid_scope_mode?
      BULK_SCOPE_MODES.include?(scope_mode)
    end
  end
end
