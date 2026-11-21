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

      user = User.find_by(id: @user_id)
      raise ActiveRecord::RecordNotFound, "Quick search user not found" unless user

      query = quick_search.fetch("query")
      search = Search.new(
        user: user,
        title: query.truncate(80),
        query_conditions: query,
        status: "processing",
        relevance_mode: Search::DEFAULT_RELEVANCE_MODE
      )
      prompt = Prompt.new(search: search, full_query_text: query, status: "active")
      builder = ResultBuilder.new(prompt: prompt)

      update_status(status: "processing", message: "Starting search engines…")

      summary = SearchEngines::ResultsCollector.call(
        query,
        {},
        on_engine_start: ->(collector_class) { engine_started(collector_class) }
      ) do |raw_results, collector_name|
        batch_results = builder.build(raw_results)
        Store.append_results(@token, batch_results.map { |result| serializable_attributes(result) })
        batch_results.each { |result| Broadcaster.result(@token, result) }

        next if batch_results.empty?

        update_status(
          active_engine: engine_label(collector_name),
          results_count: builder.count,
          message: "#{engine_label(collector_name)} returned #{batch_results.size} new results."
        )
      end

      finish_search(builder.count, summary)
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

    def engine_started(collector_class)
      label = engine_label(collector_class.name)
      update_status(active_engine: label, message: "Searching with #{label}…")
    end

    def engine_label(collector_name)
      key = collector_name.to_s.split("::")[1].to_s
      ENGINE_LABELS.fetch(key, key.presence || "search engine")
    end

    def finish_search(result_count, summary)
      failed_engines = Array(summary[:failed_engines]).uniq
      status = result_count.zero? && summary[:error].present? ? "failed" : "completed"
      message = if result_count.positive?
                  "Search complete — #{result_count} results found."
                else
                  summary[:error].presence || "Search complete — no results found."
                end
      message += " Some engines were unavailable." if result_count.positive? && failed_engines.any?

      update_status(
        status: status,
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
  end
end
