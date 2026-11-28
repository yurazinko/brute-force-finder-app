# frozen_string_literal: true

module Results
  module BulkActions
    extend ActiveSupport::Concern

    BULK_STATUS_LABELS = {
      "unread" => "Unread",
      "watched" => "Reviewed",
      "interesting" => "Starred",
      "garbage" => "Trash"
    }.freeze

    BULK_RETURN_PARAM_KEYS = %i[status d q sort show_acknowledged show_less_relevant bulk_scope].freeze

    def bulk_update
      return handle_missing_search unless @search
      return handle_invalid_bulk_action unless valid_bulk_target_status? && valid_bulk_scope?

      updated_count = Results::BulkUpdateService.new(
        search: @search,
        target_status: params[:target_status],
        visible_ids: parsed_visible_ids,
        filter_options: @filter_options,
        scope_mode: params[:bulk_scope].presence || "visible"
      ).call

      redirect_with_bulk_notice(updated_count)
    end

    private

    def handle_missing_search
      redirect_to results_path,
                  status: :see_other,
                  alert: "Bulk actions are available only inside a search."
    end

    def handle_invalid_bulk_action
      redirect_to search_path(@search, bulk_return_params),
                  status: :see_other,
                  alert: "Invalid bulk action."
    end

    def valid_bulk_target_status?
      Results::BulkUpdateService::BULK_TARGET_STATUSES.include?(params[:target_status].to_s)
    end

    def valid_bulk_scope?
      scope_mode = params[:bulk_scope].presence || "visible"
      Results::BulkUpdateService::BULK_SCOPE_MODES.include?(scope_mode)
    end

    def redirect_with_bulk_notice(updated_count)
      target_status = params[:target_status].to_s
      label = BULK_STATUS_LABELS.fetch(target_status)
      scope_label = params[:bulk_scope].to_s == "all_matching" ? "matching" : "visible"

      redirect_to search_path(@search, bulk_return_params),
                  status: :see_other,
                  notice: "Marked #{updated_count} #{scope_label} results as #{label}."
    end

    def parsed_visible_ids
      ids = Array(params[:visible_ids]).filter_map do |value|
        id = Integer(value.to_s, 10)
        id if id.positive?
      rescue ArgumentError, TypeError
        nil
      end

      ids.uniq!
      ids || []
    end

    def bulk_return_params
      BULK_RETURN_PARAM_KEYS.filter_map do |key|
        value = params[key].presence
        next if value.nil?
        next if key == :bulk_scope && value.to_s == "visible"

        [key, value]
      end.to_h
    end
  end
end
