# frozen_string_literal: true

class ResultVerificationJob < ApplicationJob
  sidekiq_options queue: :verifications, retry: 3

  sidekiq_retry_in { |count, _| [30.seconds, 2.minutes, 10.minutes][count] || 30.minutes }

  def perform(result_id, _user_id = nil)
    result = Result.find_by(id: result_id)
    return if result.nil? || result.verification_status == "verified"
    return if throttled?(result)

    keyword_groups = Results::DorkParser.parse_groups(result.search.query_conditions)
    fetch_res = Results::StreamingPageFetcher.fetch_and_match(result.url, keyword_groups: keyword_groups)

    if fetch_res.status == :verified
      apply_successful_verification(result, fetch_res, keyword_groups)
    else
      apply_failed_verification(result, fetch_res)
    end
  end

  private

  def throttled?(result)
    domain = extract_domain(result.url)
    return false unless domain

    cache_key = "domain_throttle:#{domain}"

    acquired = Rails.cache.write(cache_key, true, nx: true, expires_in: 3.seconds)

    unless acquired
      self.class.perform_in(rand(3..6).seconds, result.id)
      return true
    end

    false
  end

  def extract_domain(url)
    URI.parse(url).host
  rescue StandardError
    nil
  end

  def apply_successful_verification(result, fetch_res, keyword_groups)
    rank_result = Results::RelevanceRanker.call(result, fetch_res.text, keyword_groups, result.url)
    merged_kws = (Array(result.matched_keywords) + Array(rank_result.matched_keywords)).uniq

    result.update!(
      matched_keywords: merged_kws,
      relevance_score: rank_result.relevance_score,
      verification_status: "verified"
    )
  end

  def apply_failed_verification(result, fetch_res)
    status = fetch_res.captcha_detected? ? "unverified_captcha" : "unverified_error"
    result.update!(verification_status: status)
  end
end
