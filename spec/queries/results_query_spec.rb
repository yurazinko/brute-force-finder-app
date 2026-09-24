# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::Query, type: :query do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user, show_acknowledged: false) }

  let!(:unread_relevant) do
    create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 10, title: "Ruby")
  end
  let!(:unread_acknowledged) do
    create(:result, search: search, status: "unread", acknowledged: true, relevance_score: 20, title: "Rails")
  end
  let!(:watched_relevant) do
    create(:result, search: search, status: "watched", acknowledged: true, relevance_score: 30, title: "Watched")
  end
  let!(:unread_irrelevant) do
    create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 0, title: "Noise")
  end

  it "returns relevant unread results by default and respects the search acknowledgement setting" do
    results = described_class.call(search.results, {}, search: search)

    expect(results).to contain_exactly(unread_relevant)
  end

  it "includes acknowledged unread results when explicitly requested" do
    results = described_class.call(
      search.results,
      { show_acknowledged: "true" },
      search: search
    )

    expect(results).to contain_exactly(unread_acknowledged, unread_relevant)
  end

  it "switches the result status filter away from inbox" do
    results = described_class.call(
      search.results,
      { status: "watched", show_less_relevant: "true" },
      search: search
    )

    expect(results).to contain_exactly(watched_relevant)
  end

  it "returns less relevant results when requested" do
    results = described_class.call(
      search.results,
      { show_less_relevant: "true" },
      search: search
    )

    expect(results).to contain_exactly(unread_irrelevant)
  end

  it "applies keyword filtering before pagination" do
    results = described_class.call(
      search.results,
      { keyword: "Rails", show_acknowledged: "true" },
      search: search
    )

    expect(results).to contain_exactly(unread_acknowledged)
  end
end
