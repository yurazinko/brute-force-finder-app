# frozen_string_literal: true

class QuickSearchesController < ApplicationController
  def show
    if params[:quick_search].present?
      @quick_search = QuickSearch::Store.fetch(params[:quick_search], user_id: current_user.id)
    end

    if @quick_search
      @quick_search_token = @quick_search.fetch("token")
      @query = @quick_search.fetch("query")
      @search = build_in_memory_search(@query)
      @results = QuickSearch::Store.results(@quick_search_token, user_id: current_user.id).map do |attributes|
        Result.new(attributes).tap { |result| result.search = @search }
      end
    else
      @query = ""
      @results = []
      flash.now[:alert] = "This quick search session has expired. Start a new search." if params[:quick_search].present?
    end
  end

  def create
    query = params[:query].to_s.squish
    return redirect_to(root_path, alert: "Enter a search query.") if query.blank?
    if query.length > QuickSearch::Store::MAX_QUERY_LENGTH
      return redirect_to(
        root_path,
        alert: "Search queries are limited to #{QuickSearch::Store::MAX_QUERY_LENGTH} characters."
      )
    end

    token = SecureRandom.hex(16)
    QuickSearch::Store.create!(token: token, user_id: current_user.id, query: query)
    QuickSearchJob.perform_async(token, current_user.id)

    redirect_to root_path(quick_search: token), status: :see_other
  rescue StandardError => e
    Rails.logger.error("[QuickSearchesController] Could not start quick search: #{e.message}")
    redirect_to root_path, alert: "Could not start the search. Please try again."
  end

  private

  def build_in_memory_search(query)
    Search.new(
      user: current_user,
      title: query.truncate(80),
      query_conditions: query,
      relevance_mode: Search::DEFAULT_RELEVANCE_MODE
    )
  end
end
