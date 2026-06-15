# frozen_string_literal: true

class SearchesController < ApplicationController
  before_action :set_search, only: %i[show activate destroy]

  def index
    @searches = Search.order(created_at: :desc)
  end

  def show
    @prompts = @search.prompts.includes(:target)

    @counts = @search.results.group(:status).size
    @counts["all_clean"] = @counts.slice("unread", "watched", "interesting").values.sum

    base_results = @search.results.by_time_frame(params[:d])

    @current_status = params[:status]

    @results = case @current_status
               when "unread", "watched", "garbage", "interesting"
                 base_results.by_status(@current_status)
               else
                 base_results.without_garbage
               end

    @results = @results.order(created_at: :desc)
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

    if target_ids.any?
      if @search.activate_search!(target_ids)
        redirect_to search_path(@search),
                    notice: "Scraping pipeline successfully initialized! Check back in a few minutes."
      else
        redirect_to search_path(@search), alert: "Failed to activate search. Check system logs."
      end
    else
      redirect_to search_path(@search), alert: "Please select at least one target website to scrape."
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
end
