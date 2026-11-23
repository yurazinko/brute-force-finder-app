# frozen_string_literal: true

class QuickSearchesController < ApplicationController
  SESSION_TOKEN_KEY = :quick_search_token

  skip_before_action :authenticate_user!, only: %i[show create save_as_campaign mark_as_read clear]

  def show
    token = requested_token || session[SESSION_TOKEN_KEY]
    @quick_search = QuickSearch::Store.fetch(token) if token.present?

    if @quick_search
      assign_active_search_view_data(@quick_search)
    else
      clear_stale_session_token(token)
      assign_empty_search_view_data
    end
  end

  def create
    query = params[:query].to_s.squish
    error = validate_query(query)
    return redirect_to(root_path, alert: error) if error

    token = start_quick_search(query)
    redirect_to root_path(quick_search: token), status: :see_other
  rescue StandardError => e
    Rails.logger.error("[QuickSearchesController] Could not start quick search: #{e.message}")
    redirect_to root_path, alert: "Could not start the search. Please try again."
  end

  def save_as_campaign
    token = params[:token].to_s
    unless QuickSearch::Store.fetch(token)
      clear_stale_session_token(token)
      return redirect_to root_path, status: :see_other,
                                    alert: "This quick search has expired. Run it again to save a campaign."
    end

    session[SESSION_TOKEN_KEY] = token
    redirect_to_campaign_creation(new_search_path(quick_search_token: token))
  end

  def mark_as_read
    token = params[:token].to_s
    return head :not_found unless token.present? && session[SESSION_TOKEN_KEY].to_s == token
    return head :not_found unless QuickSearch::Store.fetch(token)

    updated_result = QuickSearch::Store.update_result!(
      token,
      url_hash: params[:url_hash],
      attributes: { status: "watched", acknowledged: true }
    )

    head(updated_result ? :no_content : :not_found)
  end

  def clear
    token = session.delete(SESSION_TOKEN_KEY)
    QuickSearch::Store.clear!(token) if token.present?

    redirect_to root_path, status: :see_other, notice: "Quick Search results cleared."
  end

  private

  def requested_token
    params[:quick_search].presence || params[:token].presence
  end

  def assign_active_search_view_data(quick_search)
    @quick_search_token = quick_search.fetch("token")
    session[SESSION_TOKEN_KEY] = @quick_search_token
    @query = quick_search.fetch("query")
    @search = build_in_memory_search(@query)
    @results = build_sorted_results(@quick_search_token, @search)
  end

  def assign_empty_search_view_data
    @quick_search_token = nil
    @query = ""
    @results = []
  end

  def clear_stale_session_token(token)
    session.delete(SESSION_TOKEN_KEY) if session[SESSION_TOKEN_KEY].to_s == token.to_s
  end

  def validate_query(query)
    return "Enter a search query." if query.blank?
    if query.length > QuickSearch::Store::MAX_QUERY_LENGTH
      return "Search queries are limited to #{QuickSearch::Store::MAX_QUERY_LENGTH} characters."
    end

    nil
  end

  def start_quick_search(query)
    token = SecureRandom.hex(16)
    user_id = current_user&.id
    QuickSearch::Store.create!(token: token, user_id: user_id, query: query)
    QuickSearchJob.perform_async(token, user_id)
    session[SESSION_TOKEN_KEY] = token
    token
  end

  def redirect_to_campaign_creation(destination)
    return redirect_to(destination) if user_signed_in?

    store_location_for(:user, destination)
    redirect_to new_user_session_path, alert: "Log in or create an account to save this search as a campaign."
  end

  def build_sorted_results(token, search)
    raw_results = QuickSearch::Store.results(token).map do |attributes|
      Result.new(attributes).tap { |result| result.search = search }
    end

    QuickSearch::ResultSorter.call(raw_results)
  end

  def build_in_memory_search(query)
    Search.new(
      user: current_user,
      title: query.truncate(80),
      query_conditions: QuickSearch::QueryFormatter.call(query),
      relevance_mode: Search::DEFAULT_RELEVANCE_MODE
    )
  end
end
