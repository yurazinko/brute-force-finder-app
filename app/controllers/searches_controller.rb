# frozen_string_literal: true

class SearchesController < ApplicationController
  before_action :set_search, only: %i[show activate destroy]

  def index
    @searches = Search.order(created_at: :desc)
  end

  def show
    @prompts = @search.prompts.includes(:target)

    @counts = @search.calculate_counters(params[:d])

    base_results = @search.results.by_time_frame(params[:d])
    @current_status = params[:status]

    @results = case @current_status
               when "unread", "watched", "garbage", "interesting"
                 base_results.by_status(@current_status)
               else
                 base_results.without_garbage.where.not(status: %w[watched interesting])
               end

    @pagy, @results = pagy(@results.order(created_at: :desc))
  end

  def new
    @search = Search.new
    @categories = Category.includes(:targets).all
  end

  def create
    @search = Search.new(search_params)
    if @search.save
      redirect_to search_path(@search), notice: "Search criteria was successfully created."
    else
      @categories = Category.includes(:targets).all
      render :new, status: :unprocessable_content
    end
  end

  def activate
    target_ids = params[:target_ids] || []

    if target_ids.blank?
      flash.now[:alert] = "Please select at least one target website to scrape."
      return respond_with_flash
    end

    if @search.activate_search!(target_ids)
      @search.reload
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to search_path(@search), notice: "Scraping pipeline successfully initialized!" }
      end
    else
      flash.now[:alert] = "Failed to activate search. Check system logs."
      respond_with_flash
    end
  end

  def destroy
    @search.destroy
    redirect_to searches_path, notice: "Search and all its results were successfully deleted."
  end

  private

  def set_search
    @search = Search.find(params.expect(:id))
  end

  def search_params
    params.expect(search: [:title, :query_conditions, :time_frame, { target_ids: [] }])
  end

  def respond_with_flash
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.prepend("flash", partial: "shared/flash") }
      format.html { redirect_to search_path(@search), alert: flash[:alert] }
    end
  end
end
