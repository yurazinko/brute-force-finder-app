# frozen_string_literal: true

class QuickSearchResultVerificationJob < ApplicationJob
  sidekiq_options queue: :verifications, retry: 0

  def perform(token, user_id, url_hash)
    quick_search = QuickSearch::Store.fetch(token, user_id: user_id)
    return unless quick_search

    attributes = QuickSearch::Store.result(token, url_hash: url_hash, user_id: user_id)
    return unless attributes && attributes["verification_status"] == "pending"

    search = build_transient_search(quick_search, user_id)
    result = Result.new(attributes).tap { |record| record.search = search }
    keyword_groups = Results::DorkParser.parse_groups(search.query_conditions)

    publish_progress(quick_search, token)

    updated_attributes = verification_attributes(result, keyword_groups)
    updated = QuickSearch::Store.update_result!(token, url_hash: url_hash, attributes: updated_attributes)
    if updated
      verified_result = Result.new(updated).tap { |record| record.search = search }
      QuickSearch::Broadcaster.replace_result(token, verified_result)
    end
  rescue StandardError => e
    Rails.logger.warn(
      "[QuickSearchResultVerificationJob] Verification failed for #{url_hash}: #{e.class}: #{e.message}"
    )
    updated = QuickSearch::Store.update_result!(
      token,
      url_hash: url_hash,
      attributes: { verification_status: "unverified_error" }
    )
    if updated && defined?(search) && search
      QuickSearch::Broadcaster.replace_result(token, Result.new(updated).tap { |record| record.search = search })
    end
  ensure
    state = QuickSearch::Store.complete_verification!(token, url_hash: url_hash) if token.present? && url_hash.present?
    QuickSearch::Broadcaster.status(token, state) if state
  end

  private

  def build_transient_search(quick_search, user_id)
    user = User.find_by(id: user_id) if user_id.present?
    query = quick_search.fetch("query")

    Search.new(
      user: user,
      title: query.truncate(80),
      query_conditions: QuickSearch::QueryFormatter.call(query),
      relevance_mode: Search::DEFAULT_RELEVANCE_MODE
    )
  end

  def publish_progress(quick_search, token)
    total = quick_search.fetch("verification_total_count", 0).to_i
    completed = quick_search.fetch("verification_completed_count", 0).to_i
    state = QuickSearch::Store.update!(
      token,
      status: "verifying",
      active_engine: "Verification",
      message: "Verifying results (#{[completed + 1, total].min}/#{total})…"
    )
    QuickSearch::Broadcaster.status(token, state) if state
  end

  def verification_attributes(result, keyword_groups)
    fetch_result = Results::StreamingPageFetcher.fetch_and_match(
      result.url,
      keyword_groups: keyword_groups
    )

    if fetch_result.captcha_detected?
      captcha_attributes(result, keyword_groups)
    elsif fetch_result.error?
      { verification_status: "unverified_error" }
    else
      rank = Results::RelevanceRanker.call(
        result,
        fetch_result.text,
        keyword_groups,
        result.url,
        strict_mode: result.search.strict_mode?
      )
      {
        relevance_score: rank.relevance_score,
        matched_keywords: (Array(result.matched_keywords) + Array(rank.matched_keywords)).uniq,
        verification_status: "verified"
      }
    end
  end

  def captcha_attributes(result, keyword_groups)
    attributes = { verification_status: "unverified_captcha" }
    candidate = Results::RelevanceRanker.captcha_candidate?(
      result.matched_keywords,
      keyword_groups,
      strict_mode: result.search.strict_mode?
    )
    if candidate
      attributes[:relevance_score] = [
        result.relevance_score.to_i,
        Results::RelevanceRanker::CAPTCHA_SCORE_FLOOR
      ].max
    end
    attributes
  end
end
