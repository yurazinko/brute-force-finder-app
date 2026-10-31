# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::Query, type: :query do
  let(:user) { create(:user) }

  context "Scenario 1: When campaign is in BALANCED mode" do
    let(:search) { create(:search, user: user, show_acknowledged: false, relevance_mode: "balanced") }

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

    it "returns relevant unread results (> 0) by default and respects the search acknowledgement setting" do
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

    it "returns less relevant results (<= 0) when requested" do
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

  context "Scenario 2: When campaign is in STRICT mode" do
    let(:search) { create(:search, user: user, show_acknowledged: false, relevance_mode: "strict") }

    let!(:fully_relevant) do
      create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 100, title: "Perfect Match")
    end
    let!(:partial_relevant) do
      create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 50, title: "Partial Match")
    end
    let!(:irrelevant) do
      create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 0, title: "No Match")
    end

    it "returns ONLY fully matching results (>= 100) by default" do
      results = described_class.call(search.results, {}, search: search)

      expect(results).to contain_exactly(fully_relevant)
    end

    it "returns partial matches and noise (< 100) when show_less_relevant is requested" do
      results = described_class.call(
        search.results,
        { show_less_relevant: "true" },
        search: search
      )

      expect(results).to contain_exactly(partial_relevant, irrelevant)
    end
  end
  context "when the global feed contains searches with different relevance modes" do
    let(:balanced_search) { create(:search, user: user, relevance_mode: "balanced") }
    let(:strict_search) { create(:search, user: user, relevance_mode: "strict") }

    let!(:balanced_match) { create(:result, search: balanced_search, status: "unread", relevance_score: 50) }
    let!(:balanced_primary_only) { create(:result, search: balanced_search, status: "unread", relevance_score: 0) }
    let!(:strict_full_match) { create(:result, search: strict_search, status: "unread", relevance_score: 100) }
    let!(:strict_partial_match) { create(:result, search: strict_search, status: "unread", relevance_score: 50) }

    it "applies each result's parent search threshold in the normal feed" do
      results = described_class.call(Result.where(search_id: [balanced_search.id, strict_search.id]), {})

      expect(results).to contain_exactly(balanced_match, strict_full_match)
    end

    it "applies the matching inverse threshold when less relevant results are requested" do
      results = described_class.call(
        Result.where(search_id: [balanced_search.id, strict_search.id]),
        { show_less_relevant: "true" }
      )

      expect(results).to contain_exactly(balanced_primary_only, strict_partial_match)
    end
  end
end
