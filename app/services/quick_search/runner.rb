# frozen_string_literal: true

module QuickSearch
  class Runner
    ENGINE_LABELS = {
      "Yacy" => "YaCy",
      "Searxng" => "SearXNG",
      "Fourget" => "4get",
      "Degoog" => "DeGoog"
    }.freeze

    def initialize(token:, user_id:)
      @token = token
      @user_id = user_id
    end

    def call
      quick_search = Store.fetch(@token, user_id: @user_id)
      return unless quick_search

      query = quick_search.fetch("query")
      engine_query = QueryFormatter.call(query)
      user = User.find_by(id: @user_id) if @user_id.present?
      search = build_transient_search(user, query, engine_query)
      prompt = Prompt.new(search: search, full_query_text: engine_query, status: "active")
      builder = ResultBuilder.new(prompt: prompt)

      update_status(status: "processing", message: "Starting search engines…", active_engine: nil)

      summary = SearchEngines::ResultsCollector.call(
        engine_query,
        { disabled_engines: [:yacy] },
        on_engine_start: ->(collector_class) { engine_started(collector_class) }
      ) do |raw_results, collector_name|
        process_batch(raw_results, collector_name, builder)
      end

      finish_or_schedule_verification(builder.count, summary)
    rescue StandardError => e
      Rails.logger.error("[QuickSearch::Runner] Search #{@token} failed: #{e.class}: #{e.message}")
      update_status(
        status: "failed",
        active_engine: nil,
        message: "The search failed. Please try again.",
        error: e.message,
        completed_at: Time.current.iso8601
      )
    end

    private

    def build_transient_search(user, query, engine_query)
      Search.new(
        user: user,
        title: query.truncate(80),
        query_conditions: engine_query,
        status: "processing",
        relevance_mode: Search::DEFAULT_RELEVANCE_MODE
      )
    end

    def process_batch(raw_results, collector_name, builder)
      batch_results = builder.build(raw_results)
      return if batch_results.empty?

      Store.append_results(@token, batch_results.map { |result| serializable_attributes(result) })
      batch_results.each { |result| Broadcaster.result(@token, result) }

      update_status(
        active_engine: engine_label(collector_name),
        results_count: builder.count,
        message: "#{engine_label(collector_name)} returned #{batch_results.size} relevant results."
      )
    end

    def engine_started(collector_class)
      label = engine_label(collector_class.name)
      update_status(active_engine: label, message: "Searching with #{label}…")
    end

    def engine_label(collector_name)
      key = collector_name.to_s.split("::")[1].to_s
      ENGINE_LABELS.fetch(key, key.presence || "search engine")
    end

    def finish_or_schedule_verification(result_count, summary)
      pending_results = Store.results(@token, user_id: @user_id).select do |result|
        result["verification_status"] == "pending"
      end

      if pending_results.any?
        state = Store.begin_verifications!(@token, pending_results.size)
        Broadcaster.status(@token, state) if state
        enqueue_verification_jobs(pending_results)
      else
        finish_search(result_count, summary)
      end
    end

    def enqueue_verification_jobs(results)
      results.each do |result|
        QuickSearchResultVerificationJob.perform_async(@token, @user_id, result.fetch("url_hash"))
      rescue StandardError => e
        Rails.logger.error("[QuickSearch::Runner] Could not enqueue verification: #{e.message}")
        updated = Store.update_result!(
          @token,
          url_hash: result.fetch("url_hash"),
          attributes: { verification_status: "unverified_error" }
        )
        Broadcaster.replace_result(@token, build_result(updated)) if updated
        state = Store.complete_verification!(@token, url_hash: result.fetch("url_hash"))
        Broadcaster.status(@token, state) if state
      end
    end

    def finish_search(result_count, summary)
      failed_engines = Array(summary[:failed_engines]).uniq
      status = result_count.zero? && summary[:error].present? ? "failed" : "completed"
      message = if result_count.positive?
                  "Search complete — #{result_count} #{'result'.pluralize(result_count)} found."
                else
                  summary[:error].presence || "Search complete — no relevant results found."
                end

      update_status(
        status: status,
        engines_finished: true,
        active_engine: nil,
        results_count: result_count,
        failed_engines: failed_engines,
        error: summary[:error],
        message: message,
        completed_at: Time.current.iso8601
      )
    end

    def update_status(attributes)
      data = Store.update!(@token, attributes)
      Broadcaster.status(@token, data) if data
      data
    end

    def serializable_attributes(result)
      result.attributes.slice(*Store::RESULT_FIELDS)
    end

    def build_result(attributes)
      result = Result.new(attributes)
      search_data = Store.fetch(@token, user_id: @user_id)
      return result unless search_data

      user = User.find_by(id: @user_id) if @user_id.present?
      result.search = build_transient_search(
        user,
        search_data.fetch("query"),
        QueryFormatter.call(search_data.fetch("query"))
      )
      result
    end
  end
end
