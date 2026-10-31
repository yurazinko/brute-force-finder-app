# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::RelevanceRanker, type: :service do
  let(:url) { "https://example.com/job/1" }
  let(:result_payload) { { "url" => url, "title" => "Senior Ruby Developer" } }
  let(:keyword_groups) { [%w[ruby rails], %w[senior lead]] }
  let(:snippet) { "Looking for a Senior Ruby Developer with Rails experience" }

  subject(:rank) do
    described_class.call(result_payload, snippet, keyword_groups, url, strict_mode: strict_mode)
  end

  let(:strict_mode) { false }

  describe ".call" do
    context "when keyword groups are empty" do
      let(:keyword_groups) { [] }

      it "returns an empty rank with zero score and verified status" do
        expect(rank.relevance_score).to eq(0)
        expect(rank.matched_keywords).to be_empty
        expect(rank.verification_status).to eq("verified")
        expect(rank.valid?).to be(true)
      end
    end

    context "when every group matches" do
      it "caps the percentage score at 100" do
        expect(rank.relevance_score).to eq(100)
        expect(rank.matched_keywords).to contain_exactly("ruby", "senior")
        expect(rank.verification_status).to eq("verified")
        expect(rank.valid?).to be(true)
      end
    end

    context "when the primary group and one supporting group match in balanced mode" do
      let(:keyword_groups) do
        [%w[ruby rails], %w[senior lead], %w[remote hybrid], %w[backend api]]
      end
      let(:snippet) { "Ruby senior engineer" }

      it "passes the balanced minimum and scores the two matched groups as a percentage" do
        expect(rank.relevance_score).to eq(50)
        expect(rank.matched_keywords).to contain_exactly("ruby", "senior")
        expect(rank.valid?).to be(true)
      end
    end

    context "when only the primary group matches in balanced mode" do
      let(:snippet) { "Ruby developer position" }

      it "retains the candidate for verification but keeps it below the normal inbox threshold" do
        expect(rank.relevance_score).to eq(0)
        expect(rank.matched_keywords).to contain_exactly("ruby")
        expect(rank.verification_status).to eq("pending")
        expect(rank.valid?).to be(true)
      end
    end

    context "when only a later group matches" do
      let(:snippet) { "A senior developer role" }

      it "applies the primary-group penalty and keeps the score at or below zero" do
        expect(rank.relevance_score).to be <= 0
        expect(rank.relevance_score).to eq(-100)
        expect(rank.matched_keywords).to contain_exactly("senior")
        expect(rank.verification_status).to eq("pending")
        expect(rank.valid?).to be(true)
      end
    end

    context "when no keyword group matches" do
      let(:snippet) { "Unrelated job description" }

      it "returns a negative score and rejects the candidate" do
        expect(rank.relevance_score).to eq(-150)
        expect(rank.matched_keywords).to be_empty
        expect(rank.verification_status).to eq("pending")
        expect(rank.valid?).to be(false)
      end
    end

    context "when several alternatives match within one group" do
      let(:strict_mode) { true }
      let(:keyword_groups) do
        [%w[ruby rails backend], %w[senior lead], %w[remote hybrid]]
      end
      let(:snippet) { "Ruby Rails backend engineer" }

      it "counts the group once rather than awarding points per matched word" do
        expect(rank.relevance_score).to eq(33)
        expect(rank.matched_keywords).to contain_exactly("ruby")
      end
    end

    context "when some of many groups match" do
      let(:keyword_groups) do
        [%w[ruby rails], %w[senior lead], %w[remote hybrid], %w[backend api]]
      end
      let(:snippet) { "Ruby remote backend engineer" }

      it "uses the percentage of matched groups, not a fixed score per keyword pair" do
        expect(rank.relevance_score).to eq(75)
        expect(rank.matched_keywords).to contain_exactly("ruby", "remote", "backend")
      end
    end

    context "when three of four groups match but the primary group does not" do
      let(:keyword_groups) do
        [%w[ruby rails], %w[senior lead], %w[remote hybrid], %w[backend api]]
      end
      let(:snippet) { "Senior remote backend engineer" }

      it "subtracts the primary-group penalty from the percentage score" do
        expect(rank.relevance_score).to eq(-75)
        expect(rank.relevance_score).to be <= 0
        expect(rank.valid?).to be(true)
      end
    end

    context "when strict mode is enabled" do
      let(:strict_mode) { true }
      let(:snippet) { "Ruby developer" }

      it "retains partial matches for the less-relevant feed without passing the strict threshold" do
        expect(rank.relevance_score).to eq(50)
        expect(rank.verification_status).to eq("pending")
        expect(rank.valid?).to be(true)
      end
    end

    context "when a query has only one group" do
      let(:keyword_groups) { [%w[ruby rails]] }
      let(:snippet) { "Rails backend engineer" }

      it "treats a match in the primary group as sufficient in balanced mode" do
        expect(rank.relevance_score).to eq(100)
        expect(rank.valid?).to be(true)
      end
    end
  end

  describe ".captcha_candidate?" do
    it "requires primary and later-group matches in balanced mode" do
      expect(described_class.captcha_candidate?(%w[ruby], keyword_groups, strict_mode: false)).to be(false)
      expect(described_class.captcha_candidate?(%w[ruby senior], keyword_groups, strict_mode: false)).to be(true)
    end

    it "allows a primary-group match to receive the CAPTCHA floor in strict mode" do
      expect(described_class.captcha_candidate?(%w[ruby], keyword_groups, strict_mode: true)).to be(true)
    end

    it "never grants the CAPTCHA floor when the primary group is missing" do
      expect(described_class.captcha_candidate?(%w[senior], keyword_groups, strict_mode: true)).to be(false)
    end
  end
end
