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

  before do
    allow(QuickSearch::Store).to receive(:fetch).with(token, user_id: user.id).and_return(quick_search)
    allow(QuickSearch::Store).to receive(:update!)
    allow(QuickSearch::Store).to receive(:append_results)
    allow(QuickSearch::Broadcaster).to receive(:status)
    allow(QuickSearch::Broadcaster).to receive(:result)

    allow(SearchEngines::ResultsCollector).to receive(:call) do |_search_query, _options, on_engine_start:, &on_batch|
      collector = SearchEngines::Yacy::RawResultsCollector
      on_engine_start.call(collector)
      on_batch.call(
        [{ url: "https://example.com/jobs/1", title: "Rails role", content: "Backend engineer", engine: "YaCy" }],
        collector.name
      )
      { failed_engines: [], error: nil }
    end
  end

  describe "#call" do
    it "streams in-memory results and does not persist Search, Prompt, or Result records" do
      expect do
        described_class.new(token: token, user_id: user.id).call
      end.not_to(change { [Search.count, Prompt.count, Result.count] })

      expect(QuickSearch::Store).to have_received(:append_results).with(
        token,
        array_including(hash_including("url" => "https://example.com/jobs/1"))
      )
      expect(QuickSearch::Broadcaster).to have_received(:result).with(token, an_instance_of(Result))
      expect(QuickSearch::Store).to have_received(:update!).with(
        token,
        hash_including(status: "completed", results_count: 1)
      )
    end
  end
end
