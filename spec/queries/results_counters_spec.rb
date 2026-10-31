# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::Counters, type: :query do
  describe ".calculate_filtered" do
    let(:user) { create(:user) }

    context "Scenario 1: When campaign is in BALANCED mode" do
      let(:search) { create(:search, user: user, show_acknowledged: false, relevance_mode: "balanced") }

      # Relevant records (relevance_score > 0)
      let!(:unread_rel) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 50) }
      let!(:unread_ack_rel) { create(:result, search: search, status: "unread", acknowledged: true, relevance_score: 50) }
      let!(:watched_rel) { create(:result, search: search, status: "watched", acknowledged: true, relevance_score: 30) }

      # Less relevant records (relevance_score <= 0)
      let!(:unread_irrel) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 0) }
      let!(:watched_irrel) { create(:result, search: search, status: "watched", acknowledged: false, relevance_score: -10) }
      let!(:garbage_irrel) { create(:result, search: search, status: "garbage", acknowledged: false, relevance_score: -5) }

      context "when show_less_relevant = false (default behavior)" do
        let(:options) { { show_less_relevant: "false", status: "unread" } }

        it "counts ONLY relevant results (> 0) for each tab" do
          counts = described_class.calculate_filtered(search.results, options, search)

          expect(counts.unread).to eq(1)
          expect(counts.watched).to eq(1)
          expect(counts.garbage).to eq(0)
        end

        it "correctly detects less relevant results (has_less_relevant)" do
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
      end
    end

    context "Scenario 2: When campaign is in STRICT mode" do
      let(:search) { create(:search, user: user, show_acknowledged: false, relevance_mode: "strict") }

      # Fully relevant records (relevance_score >= 100 - 100% group match)
      let!(:unread_rel) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 100) }
      let!(:watched_rel) { create(:result, search: search, status: "watched", acknowledged: true, relevance_score: 100) }

      # Less relevant / partial match records (< 100)
      let!(:unread_partial) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 50) }
      let!(:garbage_irrel) { create(:result, search: search, status: "garbage", acknowledged: false, relevance_score: -5) }

      context "when show_less_relevant = false" do
        let(:options) { { show_less_relevant: "false", status: "unread" } }

        it "counts ONLY fully matching results (>= 100) for each tab" do
          counts = described_class.calculate_filtered(search.results, options, search)

          expect(counts.unread).to eq(1)
          expect(counts.watched).to eq(1)
          expect(counts.garbage).to eq(0)
        end

        it "detects partial/unmatched results (< 100) as less relevant" do
          counts = described_class.calculate_filtered(search.results, options, search)
          expect(counts.has_less_relevant).to be(true)
        end
      end

      context "when show_less_relevant = true" do
        let(:options) { { show_less_relevant: "true", status: "unread" } }

        it "includes partial matches in counter sums" do
          counts = described_class.calculate_filtered(search.results, options, search)

          expect(counts.unread).to eq(2) # unread_rel + unread_partial
        end
      end
    end
  end

  describe ".bulk_calculate" do
    let(:user) { create(:user) }
    let!(:search_balanced) { create(:search, user: user, show_acknowledged: false, relevance_mode: "balanced") }
    let!(:search_strict) { create(:search, user: user, show_acknowledged: true, relevance_mode: "strict") }

    before do
      create(:result, search: search_balanced, status: "unread", acknowledged: false, relevance_score: 50)
      create(:result, search: search_balanced, status: "unread", acknowledged: false, relevance_score: 0)

      create(:result, search: search_strict, status: "unread", acknowledged: true, relevance_score: 100)
      # Змінюємо статус з garbage на unread, щоб він належав до поточної перевірюваної вкладки
      create(:result, search: search_strict, status: "unread", acknowledged: false, relevance_score: 50)
    end

    it "returns a Hash with calculated Counts respecting each search's specific relevance mode" do
      options = { show_less_relevant: "false", status: "unread" }
      results = described_class.bulk_calculate([search_balanced, search_strict], options)

      expect(results.keys).to match_array([search_balanced.id, search_strict.id])

      expect(results[search_balanced.id].unread).to eq(1)
      expect(results[search_balanced.id].has_less_relevant).to be(true)

      expect(results[search_strict.id].unread).to eq(1)
      expect(results[search_strict.id].has_less_relevant).to be(true)
    end

    it "returns an empty Hash when given an empty searches array" do
      expect(described_class.bulk_calculate([])).to eq({})
    end
  end

  describe "global feed with mixed relevance modes" do
    let(:user) { create(:user) }
    let(:balanced_search) { create(:search, user: user, relevance_mode: "balanced") }
    let(:strict_search) { create(:search, user: user, relevance_mode: "strict") }

    before do
      create(:result, search: balanced_search, status: "unread", acknowledged: false, relevance_score: 50)
      create(:result, search: balanced_search, status: "unread", acknowledged: false, relevance_score: 80)
      create(:result, search: balanced_search, status: "unread", acknowledged: false, relevance_score: 0)
      create(:result, search: strict_search, status: "unread", acknowledged: false, relevance_score: 100)
      create(:result, search: strict_search, status: "unread", acknowledged: false, relevance_score: 50)
    end

    it "uses each parent search mode for normal and less-relevant counters" do
      relation = Result.where(search_id: [balanced_search.id, strict_search.id])

      normal_counts = described_class.calculate_filtered(relation, { status: "unread" })
      expect(normal_counts.unread).to eq(3)
      expect(normal_counts.has_less_relevant).to be(true)

      less_relevant_counts = described_class.calculate_filtered(
        relation,
        { status: "unread", show_less_relevant: "true" }
      )
      expect(less_relevant_counts.unread).to eq(2)
      expect(less_relevant_counts.unread).not_to eq(normal_counts.unread)
    end
  end

  describe "Edge Cases and Data Types" do
    let(:user) { create(:user) }
    let(:search) { create(:search, user: user, relevance_mode: "balanced") }

    it "is resilient to options keys as symbols or strings (Indifferent Access)" do
      create(:result, search: search, status: "unread", relevance_score: 50)

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
