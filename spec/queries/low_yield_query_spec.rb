# frozen_string_literal: true

require "rails_helper"

RSpec.describe Targets::LowYieldQuery, type: :query do
  let(:user) { create(:user) }
  let(:category) { create(:category, user: user) }
  let(:search) { create(:search, user: user) }

  let!(:active_target) do
    create(:target, category: category, name: "Active Low Yield", domain: "lowyield.com", is_active: true)
  end

  let!(:inactive_target) do
    create(:target, category: category, name: "Inactive Target", domain: "inactive.com", is_active: false)
  end

  let!(:productive_target) do
    create(:target, category: category, name: "High Yield", domain: "productive.com", is_active: true)
  end

  describe ".call" do
    context "when targets have prompts but zero results" do
      before do
        create_list(:prompt, 25, search: search, target: active_target, status: "active", created_at: 5.days.ago)

        create_list(:prompt, 15, search: search, target: productive_target, status: "active", created_at: 5.days.ago)

        create(
          :result,
          search: search,
          target: productive_target,
          url: "https://productive.com/item1",
          relevance_score: 5,
          created_at: 2.days.ago
        )
      end

      it "identifies zero-result targets and excludes productive or inactive ones" do
        results = described_class.call(since: 30.days.ago, limit: 5)

        expect(results.map(&:target)).to include(active_target)
        expect(results.map(&:target)).not_to include(productive_target)
        expect(results.map(&:target)).not_to include(inactive_target)
      end

      it "calculates correct prompt count and zero results" do
        stats = described_class.call(since: 30.days.ago, limit: 5).first

        expect(stats.prompts_count).to eq(25)
        expect(stats.relevant_results_count).to eq(0)
        expect(stats.yield_percentage).to eq(0.0)
      end
    end
  end
end
