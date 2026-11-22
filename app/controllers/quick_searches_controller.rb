# frozen_string_literal: true

class QuickSearchesController < ApplicationController
  SESSION_TOKEN_KEY = :quick_search_token

  skip_before_action :authenticate_user!, only: %i[show create save_as_campaign clear]

  def show
    requested_token = params[:quick_search].presence || params[:token].presence
    token = requested_token || session[SESSION_TOKEN_KEY]
    @quick_search = QuickSearch::Store.fetch(token) if token.present?

    if @quick_search
      @quick_search_token = @quick_search.fetch("token")
      session[SESSION_TOKEN_KEY] = @quick_search_token
      @query = @quick_search.fetch("query")
      @search = build_in_memory_search(@query)
      @results = QuickSearch::ResultSorter.call(
        QuickSearch::Store.results(@quick_search_token).map do |attributes|
          Result.new(attributes).tap { |result| result.search = @search }
        end
      )
    else
      session.delete(SESSION_TOKEN_KEY) if session[SESSION_TOKEN_KEY].to_s == token.to_s
      @quick_search_token = nil
      @query = ""
      @results = []
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
    user_id = current_user&.id
    QuickSearch::Store.create!(token: token, user_id: user_id, query: query)
    QuickSearchJob.perform_async(token, user_id)
    session[SESSION_TOKEN_KEY] = token

    redirect_to root_path(quick_search: token), status: :see_other
  rescue StandardError => e
    Rails.logger.error("[QuickSearchesController] Could not start quick search: #{e.message}")
    redirect_to root_path, alert: "Could not start the search. Please try again."
  end

  def save_as_campaign
    token = params[:token].to_s
    quick_search = QuickSearch::Store.fetch(token)
    unless quick_search
      session.delete(SESSION_TOKEN_KEY) if session[SESSION_TOKEN_KEY].to_s == token
      return redirect_to root_path, status: :see_other,
                                    alert: "This quick search has expired. Run it again to save a campaign."
    end

    session[SESSION_TOKEN_KEY] = token
    destination = new_search_path(quick_search_token: token)
    if user_signed_in?
      redirect_to destination
    else
      store_location_for(:user, destination)
      redirect_to new_user_session_path, alert: "Log in or create an account to save this search as a campaign."
    end
  end

  def clear
    token = session.delete(SESSION_TOKEN_KEY)
    QuickSearch::Store.clear!(token) if token.present?

    redirect_to root_path, status: :see_other, notice: "Quick Search results cleared."
  end

  private

  def build_in_memory_search(query)
    Search.new(
      user: current_user,
      title: query.truncate(80),
      query_conditions: QuickSearch::QueryFormatter.call(query),
      relevance_mode: Search::DEFAULT_RELEVANCE_MODE
    )
  end
end
