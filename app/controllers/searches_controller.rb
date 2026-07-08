# frozen_string_literal: true

class SearchesController < ApplicationController
  include ResultFilterable

  before_action :set_search, only: %i[show edit update activate destroy]
  before_action :set_categories_for_form, only: %i[new edit create update]

  def index
    @searches = Search.order(created_at: :desc)
    @raw_counts = Result.where(search_id: @searches.pluck(:id)).group(:search_id, :status, :acknowledged).count
  end

  def show
    @prompts = @search.prompts.includes(:target)

    filtered_results = filter_results(@search.results)
    @counts = calculate_counters_for(@search.results)

    @pagy, @results = pagy(filtered_results.order(sorting_order))
  end

  def new = @search = Search.new

  def edit; end

  def create
    @search = Search.new(search_params)
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
        format.turbo_stream
        format.html { redirect_to search_path(@search), notice: "Scraping pipeline successfully initialized!" }
      end
    else
      respond_with_flash("Failed to activate search. Check system logs.")
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

  def respond_with_flash(alert_msg)
    flash.now[:alert] = alert_msg
    respond_to do |f|
      f.html { redirect_to search_path(@search), alert: alert_msg }
      f.turbo_stream { render turbo_stream: turbo_stream.prepend("flash", partial: "layouts/flash") }
    end
  end

  def handle_successful_update
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = "Search criteria was successfully updated."
        render turbo_stream: [
          turbo_stream.replace("search_lifecycle_status", partial: "searches/status_badge",
                                                          locals: { search: @search }),
          turbo_stream.prepend("flash", partial: "layouts/flash")
        ]
      end
      format.html { redirect_to determine_update_redirect_path, notice: "Search criteria was successfully updated." }
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
