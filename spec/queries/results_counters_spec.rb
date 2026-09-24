# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::Counters, type: :query do
  describe ".calculate" do
    it "returns calculated status counts without additional filters" do
      create(:result, status: "unread")
      create_list(:result, 2, status: "watched")
      create_list(:result, 3, status: "interesting")
      create(:result, status: "garbage")

      counts = described_class.calculate(Result.all)

      expect(counts.unread).to eq(1)
      expect(counts.watched).to eq(2)
      expect(counts.interesting).to eq(3)
      expect(counts.garbage).to eq(1)
      expect(counts.has_less_relevant).to be(false)
      expect(counts.all_clean).to eq(6)
      expect(counts.total).to eq(7)
    end
  end

  describe ".calculate_filtered" do
    let(:user) { create(:user) }
    let(:search) { create(:search, user: user, show_acknowledged: false) }

    # Relevant records (relevance_score > 0)
    let!(:unread_rel) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 10) }
    let!(:unread_ack_rel) { create(:result, search: search, status: "unread", acknowledged: true, relevance_score: 10) }
    let!(:watched_rel) { create(:result, search: search, status: "watched", acknowledged: true, relevance_score: 5) }

    # Less relevant records (relevance_score <= 0)
    let!(:unread_irrel) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 0) }
    let!(:watched_irrel) { create(:result, search: search, status: "watched", acknowledged: false, relevance_score: -10) }
    let!(:garbage_irrel) { create(:result, search: search, status: "garbage", acknowledged: false, relevance_score: -5) }

    context "when show_less_relevant = false (default behavior)" do
      let(:options) { { show_less_relevant: "false", status: "unread" } }

      it "counts ONLY relevant results for each tab" do
        counts = described_class.calculate_filtered(search.results, options, search)

        expect(counts.unread).to eq(1)
        expect(counts.watched).to eq(1) # watched_rel
        expect(counts.garbage).to eq(0) # garbage_irrel is excluded because it is irrelevant
      end

      it "correctly detects the presence of less relevant results (has_less_relevant)" do
        counts = described_class.calculate_filtered(search.results, options, search)

        expect(counts.has_less_relevant).to be(true)
      end
    end

    context "when show_less_relevant = true" do
      let(:options) { { show_less_relevant: "true", status: "unread" } }

      it "includes less relevant records in total counter sums" do
        counts = described_class.calculate_filtered(search.results, options, search)

        expect(counts.unread).to eq(2) # unread_rel + unread_irrel
        expect(counts.watched).to eq(2) # watched_rel + watched_irrel
        expect(counts.garbage).to eq(1) # garbage_irrel
      end
    end

    context "acknowledged status handling logic" do
      it "includes acknowledged records in unread count when search.show_acknowledged == true" do
        search.update!(show_acknowledged: true)
        options = { show_less_relevant: "true", status: "unread" }

        counts = described_class.calculate_filtered(search.results, options, search)

        expect(counts.unread).to eq(3)
      end

      it "does NOT apply acknowledged constraints to other tabs (watched/garbage/interesting)" do
        create(:result, search: search, status: "watched", acknowledged: true, relevance_score: 10)
        options = { show_less_relevant: "true", status: "watched" }

        counts = described_class.calculate_filtered(search.results, options, search)

        expect(counts.watched).to eq(3)
      end
    end

    context "has_less_relevant flag isolation per active tab" do
      it "returns false for has_less_relevant if the currently selected tab has no less relevant items" do
        options = { status: "interesting", show_less_relevant: "false" }

        counts = described_class.calculate_filtered(search.results, options, search)

        expect(counts.has_less_relevant).to be(false)
      end
    end
  end

  describe ".bulk_calculate" do
    let(:user) { create(:user) }
    let!(:search_a) { create(:search, user: user, show_acknowledged: false) }
    let!(:search_b) { create(:search, user: user, show_acknowledged: true) }

    before do
      create(:result, search: search_a, status: "unread", acknowledged: false, relevance_score: 10)
      create(:result, search: search_a, status: "unread", acknowledged: false, relevance_score: 0) # irrel

      create(:result, search: search_b, status: "unread", acknowledged: true, relevance_score: 15)
      create(:result, search: search_b, status: "garbage", acknowledged: false, relevance_score: 10)
    end

    it "returns a Hash with calculated Counts for each search_id" do
      options = { show_less_relevant: "false", status: "unread" }
      results = described_class.bulk_calculate([search_a, search_b], options)

      expect(results.keys).to match_array([search_a.id, search_b.id])

      expect(results[search_a.id].unread).to eq(1)
      expect(results[search_a.id].has_less_relevant).to be(true)

      expect(results[search_b.id].unread).to eq(1)
      expect(results[search_b.id].garbage).to eq(1)
      expect(results[search_b.id].has_less_relevant).to be(false)
    end

    it "returns an empty Hash when given an empty searches array" do
      expect(described_class.bulk_calculate([])).to eq({})
    end
  end

  describe "Edge Cases and Data Types" do
    let(:user) { create(:user) }
    let(:search) { create(:search, user: user) }

    it "is resilient to options keys as symbols or strings (Indifferent Access)" do
      create(:result, search: search, status: "unread", relevance_score: 10)

      symbol_counts = described_class.calculate_filtered(search.results, { show_less_relevant: "true" }, search)
      string_counts = described_class.calculate_filtered(search.results, { "show_less_relevant" => "true" }, search)

      expect(symbol_counts.unread).to eq(string_counts.unread)
    end

    it "correctly casts relevance_score <= 0 database values (Boolean Casting)" do
      raw_counts = {
        ["unread", false, 1] => 2,      # 1 (truthy - is_less_relevant)
        ["unread", false, "t"] => 1,    # "t" (truthy - is_less_relevant)
        ["unread", false, false] => 3   # false (relevant item)
      }

      relation = search.results
      allow(relation).to receive(:by_time_frame).and_return(relation)
      allow(relation).to receive(:search_by_keyword).and_return(relation)
      allow(relation).to receive_message_chain(:group, :count).and_return(raw_counts)

      counts = described_class.calculate_filtered(relation, { show_less_relevant: "false" }, search)

      expect(counts.unread).to eq(3)
    end
  end
end
