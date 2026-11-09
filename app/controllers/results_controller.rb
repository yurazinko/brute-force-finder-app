# frozen_string_literal: true

class ResultsController < ApplicationController
  include ResultFilterable

  BULK_STATUS_LABELS = {
    "unread" => "Unread",
    "watched" => "Reviewed",
    "interesting" => "Starred",
    "garbage" => "Trash"
  }.freeze

  BULK_RETURN_PARAM_KEYS = %i[status d q sort show_acknowledged show_less_relevant].freeze

  before_action :find_result, only: :update
  before_action :set_scopes_and_options

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def index
    @selected_search_ids = params[:search_ids] || []
    @available_searches = current_user.searches.order(created_at: :desc)

    fetch_filtered_results(@base_scope, @filter_options)

    respond_to do |format|
      format.html { render "searches/show" if params[:turbo_frame].present? }
      format.html
      format.turbo_stream
    end
  end

  def update
    update_success = if result_params[:status].present?
                       Results::UpdateStatusService.new(result: @result, status: result_params[:status]).call
                     else
                       @result.update(result_params)
                     end

    head :unprocessable_content and return unless update_success

    prepare_update_variables
    respond_to_successful_update
  end

  def bulk_update
    return handle_missing_search unless @search
    return handle_invalid_bulk_action unless valid_bulk_target_status?

    updated_count = Results::BulkUpdateService.new(
      search: @search,
      target_status: params[:target_status],
      visible_ids: parsed_visible_ids,
      filter_options: @filter_options
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

  def redirect_with_bulk_notice(updated_count)
    target_status = params[:target_status].to_s
    label = BULK_STATUS_LABELS.fetch(target_status)

    redirect_to search_path(@search, bulk_return_params),
                status: :see_other,
                notice: "Marked #{updated_count} visible results as #{label}."
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
    BULK_RETURN_PARAM_KEYS.each_with_object({}) do |key, result|
      value = params[key]
      result[key] = value unless value.nil? || value == ""
    end
  end

  def find_result
    @result = current_user.results.find(params.expect(:id))
  end

  def render_not_found
    head :not_found
  end

  def set_scopes_and_options
    @search = current_user.searches.find_by(id: params[:search_id])

    @base_scope = if @search
                    @search.results
                  elsif params[:search_ids].present?
                    current_user.results.where(search_id: params[:search_ids])
                  else
                    current_user.results
                  end

    @filter_options = parse_filter_options(search_instance: @search)
  end

  def prepare_update_variables
    visible_ids = params[:visible_ids] || []

    @next_card = Results::FeedRefill.next_card(
      base_scope: @base_scope,
      removed_id: @result.id,
      visible_ids: visible_ids,
      options: @filter_options,
      search: @search
    )

    @counts = Results::Counters.calculate_filtered(@base_scope, @filter_options, @search)
  end

  def respond_to_successful_update
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_update_payload }
      format.html { redirect_after_update }
    end
  end

  def turbo_stream_update_payload
    streams = [
      turbo_stream.remove(@result),
      turbo_stream.replace(
        "search_tabs_navigation",
        partial: "searches/tabs_counters",
        locals: { search: @search, counts: @counts }
      )
    ]

    if @next_card
      streams << turbo_stream.append("results_pool_list", partial: "results/result_card",
                                                          locals: { result: @next_card })
    end

    streams
  end

  def redirect_after_update
    if @search.present?
      redirect_to search_path(@search, common_params)
    else
      redirect_to results_path(common_params.merge(search_ids: params[:search_ids]))
    end
  end

  def result_params
    params.expect(result: %i[status acknowledged])
  end

  def common_params
    @common_params ||= {
      status: params[:status],
      d: params[:d],
      q: params[:q],
      sort: params[:sort],
      show_acknowledged: params[:show_acknowledged],
      show_less_relevant: params[:show_less_relevant]
    }
  end
end
