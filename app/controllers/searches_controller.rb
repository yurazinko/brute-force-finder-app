# frozen_string_literal: true

class SearchesController < ApplicationController
  include ResultFilterable

  before_action :set_search, only: %i[show edit update activate destroy toggle_pause complete]
  before_action :set_categories_for_form, only: %i[new show edit create update]
  before_action :set_search_campaign_state, only: %i[new]

  def index
    @searches = current_user.searches.order(created_at: :desc)
    filters = parse_filter_options
    @bulk_counts = Results::Counters.bulk_calculate(@searches, filters)
  end

  def show
    @base_scope = @search.results
    @filter_options = parse_filter_options(search_instance: @search)

    fetch_filtered_results(@base_scope, @filter_options)

    respond_to do |format|
      format.html
      format.turbo_stream { render "results/index" }
    end
  end

  def new
    state = @search_campaign_state

    @search = state.search
    @form_back_path = state.back_path
    @form_back_label = state.back_label
    @quick_search_token = state.quick_search_token
    session[QuickSearchesController::SESSION_TOKEN_KEY] = @quick_search_token if @quick_search_token.present?
    flash.now[:alert] = state.alert if state.alert.present?
  end

  def edit; end

  def create
    @search = current_user.searches.build(search_params)

    if @search.save
      imported_results_count = import_quick_search_results
      redirect_to search_path(@search), notice: campaign_creation_notice(imported_results_count)
    else
      @quick_search_token = params[:quick_search_token].presence
      @form_back_path = root_path(quick_search: @quick_search_token) if @quick_search_token.present?
      @form_back_label = "Back to Quick Search Results" if @quick_search_token.present?
      render :new, status: :unprocessable_content
    end
  end

  def update = @search.update(search_params) ? handle_successful_update : handle_failed_update

  def activate
    target_ids = params[:target_ids] || []

    if @search.activate_search!(target_ids)
      @search.reload

      respond_to do |format|
        format.html { redirect_to search_path(@search), notice: "Scraping pipeline successfully initialized!" }
        format.turbo_stream { render "searches/update", status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to search_path(@search), alert: "Failed to activate search. Check system logs." }
        format.turbo_stream { render turbo_stream: turbo_stream.prepend("flash", partial: "layouts/flash") }
      end
    end
  end

  def toggle_pause
    paused = @search.paused?

    paused ? @search.resume! : @search.pause!

    notice = paused ? "Campaign resumed." : "Campaign paused."

    respond_to do |format|
      format.html { redirect_back_or_to search_path(@search), notice: notice }
      format.turbo_stream { render "searches/update", status: :ok }
    end
  end

  def complete
    @search.force_complete!

    respond_to do |format|
      format.html { redirect_back_or_to search_path(@search), notice: "Campaign completed." }
      format.turbo_stream { render "searches/update", status: :ok }
    end
  end

  def destroy
    @search.destroy
    redirect_to searches_path, notice: "Search and all its results were successfully deleted."
  end

  private

  def import_quick_search_results
    token = params[:quick_search_token].to_s
    return if token.blank? || session[QuickSearchesController::SESSION_TOKEN_KEY].to_s != token

    SearchCampaigns::QuickSearchResultsImporter.new(search: @search, token: token).call
  rescue StandardError => e
    Rails.logger.error("[SearchesController] Quick Search result import failed: #{e.class}: #{e.message}")
    nil
  end

  def campaign_creation_notice(imported_results_count)
    return "Search criteria was successfully created." if params[:quick_search_token].blank?
    if imported_results_count.nil?
      return "Search campaign was created, but the Quick Search session expired; no results were transferred."
    end
    if imported_results_count.zero?
      return "Search criteria was successfully created; no Quick Search results were available to transfer."
    end

    label = imported_results_count == 1 ? "result" : "results"
    "Search criteria was successfully created; #{imported_results_count} Quick Search #{label} transferred."
  end

  def set_search_campaign_state
    @search_campaign_state = SearchCampaigns::FormBuilder.new(
      user: current_user,
      params: params,
      root_path: ->(query = {}) { root_path(query) },
      list_path: searches_path
    ).call
  end

  def set_search = @search = current_user.searches.find(params.expect(:id))

  def search_params
    params.expect(
      search: [:title, :query_conditions, :time_frame, :show_acknowledged, :relevance_mode, { target_ids: [] }]
    )
  end

  def set_categories_for_form = @categories = current_user.categories.includes(:active_targets).order(:name)

  def handle_successful_update
    respond_to do |format|
      format.html { redirect_to determine_update_redirect_path, notice: "Search criteria was successfully updated." }
      format.turbo_stream { render "searches/update", status: :ok }
    end
  end

  def handle_failed_update
    respond_to do |format|
      format.html { render :edit, status: :unprocessable_content }
      format.turbo_stream do
        flash.now[:alert] = @search.errors.full_messages.to_sentence
        render turbo_stream: turbo_stream.prepend("flash", partial: "layouts/flash")
      end
    end
  end

  def determine_update_redirect_path
    if request.referer&.include?(searches_path) && !request.referer&.include?(search_path(@search))
      searches_path
    else
      search_path(@search)
    end
  end

  def build_clone_search(donor)
    current_user.searches.build(
      title: "#{donor.title} (Copy)",
      query_conditions: donor.query_conditions,
      time_frame: donor.time_frame,
      show_acknowledged: donor.show_acknowledged,
      relevance_mode: donor.relevance_mode,
      target_ids: donor.target_ids
    )
  end
end
