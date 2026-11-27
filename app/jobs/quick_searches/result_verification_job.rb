# frozen_string_literal: true

module QuickSearches
  class ResultVerificationJob < ApplicationJob
    sidekiq_options queue: :verifications, retry: 0

    def perform(token, user_id, url_hash)
      @token = token
      @user_id = user_id
      @url_hash = url_hash
      @search = nil

      return unless pending_verification_needed?

      @search = build_transient_search
      result = build_result(load_attributes)
      keyword_groups = Results::DorkParser.parse_groups(@search.query_conditions)

      publish_progress
      persist_and_broadcast(verification_attributes(result, keyword_groups))
    rescue StandardError => e
      handle_verification_error(e)
    ensure
      finalize_verification
    end

    private

    attr_reader :token, :user_id, :url_hash, :search

    def pending_verification_needed?
      @quick_search = QuickSearch::Store.fetch(token, user_id: user_id)
      return false unless @quick_search

      attributes = load_attributes
      attributes.present? && attributes["verification_status"] == "pending"
    end

    def load_attributes
      QuickSearch::Store.result(token, url_hash: url_hash, user_id: user_id)
    end

    def build_transient_search
      user = user_id.present? ? User.find_by(id: user_id) : nil
      query = @quick_search.fetch("query")

      Search.new(
        user: user,
        title: query.truncate(80),
        query_conditions: QuickSearch::QueryFormatter.call(query),
        relevance_mode: Search::DEFAULT_RELEVANCE_MODE
      )
    end

    def build_result(attributes)
      Result.new(attributes).tap { |record| record.search = search }
    end

    def publish_progress
      total = @quick_search.fetch("verification_total_count", 0).to_i
      completed = @quick_search.fetch("verification_completed_count", 0).to_i
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
        verified_attributes(result, fetch_result, keyword_groups)
      end
    end

    def verified_attributes(result, fetch_result, keyword_groups)
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

    def persist_and_broadcast(attributes)
      updated = QuickSearch::Store.update_result!(token, url_hash: url_hash, attributes: attributes)
      return unless updated && search

      QuickSearch::Broadcaster.replace_result(token, build_result(updated))
    end

    def handle_verification_error(error)
      Rails.logger.warn(
        "[QuickSearches::Results::VerificationJob] Verification failed for #{url_hash}: #{error.class}: #{error.message}"
      )
      persist_and_broadcast(verification_status: "unverified_error")
    end

    def finalize_verification
      return unless token.present? && url_hash.present?

      state = QuickSearch::Store.complete_verification!(token, url_hash: url_hash)
      QuickSearch::Broadcaster.status(token, state) if state
    end
  end
end
