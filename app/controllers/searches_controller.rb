# frozen_string_literal: true

class SearchesController < ApplicationController
  before_action :set_search, only: %i[show activate destroy]

  def index
    @searches = Search.order(created_at: :desc)
  end

  def show
    @prompts = @search.prompts.includes(:target)
    @results = @search.results.order(created_at: :desc)
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
    params.expect(search: [:title, :query_conditions, { target_ids: [] }])
  end
end
