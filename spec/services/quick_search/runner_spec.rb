# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuickSearch::Runner, type: :service do
  let(:user) { create(:user) }
  let(:token) { SecureRandom.hex(16) }
  let(:query) { "Ruby on Rails jobs" }
  let(:quick_search) do
    {
      "token" => token,
      "user_id" => user.id,
      "query" => query
    }
  end
  let(:search_result) do
    {
      "url" => "https://example.com/jobs/1",
      "url_hash" => "hash-1",
      "title" => "Ruby on Rails developer",
      "content" => "Ruby on Rails jobs for backend engineers",
      "engine" => "SearXNG",
      "status" => "unread",
      "acknowledged" => false,
      "relevance_score" => 100,
      "matched_keywords" => %w[Ruby Rails jobs],
      "verification_status" => "verified"
    }
  end

  before do
    allow(QuickSearch::Store).to receive(:fetch).with(token, user_id: user.id).and_return(quick_search)
    allow(QuickSearch::Store).to receive(:update!).and_return(quick_search)
    allow(QuickSearch::Store).to receive(:append_results)
    allow(QuickSearch::Store).to receive(:results).with(token, user_id: user.id).and_return([search_result])
    allow(QuickSearch::Broadcaster).to receive(:status)
    allow(QuickSearch::Broadcaster).to receive(:result)

    allow(SearchEngines::ResultsCollector).to receive(:call) do |_search_query, options, on_engine_start:, &on_batch|
      expect(options).to include(disabled_engines: [:yacy])
      expect(options).not_to have_key(:yacy)

      collector = SearchEngines::Searxng::RawResultsCollector
      on_engine_start.call(collector)
      on_batch.call(
        [{
          url: "https://example.com/jobs/1",
          title: "Ruby on Rails developer",
          content: "Ruby on Rails jobs for backend engineers",
          engine: "SearXNG"
        }],
        collector.name
      )
      { failed_engines: [], error: nil }
    end
  end

  describe "#call" do
    it "quotes search terms, skips YaCy, ranks transient results and does not persist models" do
      expect do
        described_class.new(token: token, user_id: user.id).call
      end.not_to(change { [Search.count, Prompt.count, Result.count] })

      expect(SearchEngines::ResultsCollector).to have_received(:call).with(
        '"Ruby" "on" "Rails" "jobs"',
        { disabled_engines: [:yacy] },
        on_engine_start: kind_of(Proc)
      )
      expect(QuickSearch::Store).to have_received(:append_results).with(
        token,
        array_including(hash_including("url" => "https://example.com/jobs/1", "relevance_score" => 100))
      )
      expect(QuickSearch::Broadcaster).to have_received(:result).with(token, an_instance_of(Result))
      expect(QuickSearch::Store).to have_received(:update!).with(
        token,
        hash_including(status: "completed", results_count: 1)
      )
    end

    it "schedules page verification when the engine snippets contain only partial matches" do
      allow(QuickSearch::Store).to receive(:results).with(token, user_id: user.id).and_return([
                                                                                                search_result.merge("verification_status" => "pending", "relevance_score" => 25)
                                                                                              ])
      allow(QuickSearches::ResultVerificationJob).to receive(:perform_async)

      allow(SearchEngines::ResultsCollector).to receive(:call) do |_search_query, _options, on_engine_start:, &on_batch|
        collector = SearchEngines::Searxng::RawResultsCollector
        on_engine_start.call(collector)
        on_batch.call(
          [{ url: "https://example.com/jobs/1", title: "Ruby", content: "Ruby role", engine: "SearXNG" }],
          collector.name
        )
        { failed_engines: [], error: nil }
      end

      described_class.new(token: token, user_id: user.id).call

      expect(QuickSearch::Store).to have_received(:update!).with(
        token,
        hash_including(status: "verifying", verification_total_count: 1, verification_pending_count: 1)
      )
      expect(QuickSearches::ResultVerificationJob).to have_received(:perform_async).with(token, user.id, "hash-1")
    end
  end
end
