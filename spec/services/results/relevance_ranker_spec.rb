# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::RelevanceRanker, type: :service do
  let(:url) { "https://example.com/job/1" }
  let(:result_payload) { { "url" => url, "title" => "Senior Ruby Developer" } }
  let(:keyword_groups) { [%w[ruby rails], %w[senior lead]] }
  let(:snippet) { "Looking for a Senior Ruby Developer with Rails experience" }

  subject { described_class.call(result_payload, snippet, keyword_groups, url) }

  describe ".call" do
    context "when keyword_groups is empty" do
      let(:keyword_groups) { [] }

      it "returns empty rank with zero score and verified status" do
        rank = subject
        expect(rank.relevance_score).to eq(0)
        expect(rank.matched_keywords).to be_empty
        expect(rank.verification_status).to eq("verified")
        expect(rank.valid?).to be true
      end
    end

    context "when all keyword groups match directly in the snippet" do
      it "returns verified rank without needing background verification" do
        rank = subject
        expect(rank.relevance_score).to eq(200) # 2 groups * 100
        expect(rank.matched_keywords).to contain_exactly("ruby", "senior")
        expect(rank.verification_status).to eq("verified")
        expect(rank.valid?).to be true
      end
    end

    context "when snippet covers only part of the keyword groups" do
      let(:snippet) { "Looking for a Senior Developer" } # matches 2nd group only

      it "assigns pending status for background verification" do
        rank = subject
        # 1 matched group (100) - First group missing penalty (250) = -150
        expect(rank.relevance_score).to eq(-150)
        expect(rank.matched_keywords).to contain_exactly("senior")
        expect(rank.verification_status).to eq("pending")
        expect(rank.valid?).to be true # valid because pending results are kept for async check
      end
    end

    context "when no keywords match in the snippet" do
      let(:snippet) { "Unrelated job description" }

      it "assigns pending status with negative score due to missing first group" do
        rank = subject
        expect(rank.matched_keywords).to be_empty
        expect(rank.verification_status).to eq("pending")
        # 0 matched groups - FIRST_GROUP_PENALTY (250) = -250
        expect(rank.relevance_score).to eq(-250)
        expect(rank.valid?).to be true # valid because of pending status
      end
    end
  end
end
