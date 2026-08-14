# frozen_string_literal: true

class SearchesController < ApplicationController
  include ResultFilterable

  before_action :set_search, only: %i[show edit update activate destroy toggle_pause complete]
  before_action :set_categories_for_form, only: %i[new edit create update]

  def index
    @searches = Search.order(created_at: :desc)
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

  def new = @search = Search.new

  def edit; end

  def create
    @search = current_user.searches.build(search_params)

    if @search.save
      redirect_to search_path(@search), notice: "Search criteria was successfully created."
    else
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

  def set_search = @search = Search.find(params.expect(:id))

  def search_params
    params.expect(search: [:title, :query_conditions, :time_frame, :show_acknowledged, { target_ids: [] }])
  end

  def set_categories_for_form = @categories = Category.includes(:targets).all

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
end
