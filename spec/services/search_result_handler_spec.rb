# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::ResultHandler, type: :service do
  let(:user) { User.create!(username: "handler@example.com", password: "password123") }
  let(:search) { Search.create!(user: user, title: "Ruby Jobs", query_conditions: "ruby") }
  let(:prompt) { Prompt.create!(search: search, full_query_text: "site:github.com ruby", status: "active") }
  let(:raw_results) do
    { data: [{ "url" => "https://github.com/ruby/ruby", "title" => "Ruby Repo" }] }
  end

  it "persists, batch-broadcasts results, schedules debounced counters, and returns a total" do
    persisted = double(id: 123)
    allow(Results::DataTransformer).to receive(:process).and_return([{ url: "https://github.com/ruby/ruby" }])
    allow(Results::BatchPersister).to receive(:call).and_return(
      raw_count: 1, new_count: 1, persisted_results: [persisted]
    )
    allow(SearchCampaigns::LifecycleNotifier).to receive(:broadcast_new_results)
    allow(SearchCampaigns::CountersRefreshScheduler).to receive(:schedule)

    create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 100)
    create(:result, search: search, status: "watched", acknowledged: false, relevance_score: 100)
    create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 0)

    result = described_class.call(prompt, raw_results)

    expect(result).to include(raw_count: 1, new_count: 1, total: 3)
    expect(SearchCampaigns::LifecycleNotifier).to have_received(:broadcast_new_results).with(search, [persisted])
    expect(SearchCampaigns::CountersRefreshScheduler).to have_received(:schedule).with(search)
  end

  it "returns zero metrics without scheduling work for blank results" do
    expect(SearchCampaigns::CountersRefreshScheduler).not_to receive(:schedule)
    expect(SearchCampaigns::LifecycleNotifier).not_to receive(:broadcast_new_results)

    expect(described_class.call(prompt, { data: [] })).to eq(raw_count: 0, new_count: 0)
  end

  it "reports and re-raises processing failures so Sidekiq can retry" do
    error = StandardError.new("database unavailable")
    allow(Results::DataTransformer).to receive(:process).and_raise(error)
    allow(Rails.error).to receive(:report)

    expect { described_class.call(prompt, raw_results) }.to raise_error(error)
    expect(Rails.error).to have_received(:report).with(
      error,
      handled: false,
      severity: :error,
      context: { prompt_id: prompt.id, search_id: search.id }
    )
  end
end
