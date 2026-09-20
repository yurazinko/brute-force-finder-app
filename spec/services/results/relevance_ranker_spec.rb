# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::RelevanceRanker, type: :service do
  let(:url) { "https://example.com/job/1" }
  let(:result_payload) { { "url" => url, "title" => "Senior Ruby Developer" } }
  let(:keyword_groups) { [%w[ruby rails], %w[senior lead]] }
  let(:snippet) { "Looking for a Senior Ruby Developer with Rails experience" }

  let(:fetch_response) do
    instance_double(
      "PageFetcher::Response",
      status: :verified,
      text: "Full job description for Senior Ruby Developer",
      captcha_detected?: false
    )
  end

  subject { described_class.call(result_payload, snippet, keyword_groups, url) }

  describe ".call" do
    context "when keyword_groups is empty" do
      let(:keyword_groups) { [] }

      it "returns empty rank with zero score and verified status" do
        expect(Results::PageFetcher).not_to receive(:fetch)

        rank = subject
        expect(rank.relevance_score).to eq(0)
        expect(rank.matched_keywords).to be_empty
        expect(rank.verification_status).to eq("verified")
        expect(rank.valid?).to be true
      end
    end

    context "when all keyword groups match directly in the snippet" do
      it "returns verified rank without fetching the external page" do
        expect(Results::PageFetcher).not_to receive(:fetch)

        rank = subject
        expect(rank.relevance_score).to eq(200) # 2 groups * 100
        expect(rank.matched_keywords).to contain_exactly("ruby", "senior")
        expect(rank.verification_status).to eq("verified")
        expect(rank.valid?).to be true
      end
    end

    context "when snippet covers only part of the keyword groups" do
      let(:snippet) { "Looking for a Senior Developer" } # matches 2nd group only

      before do
        allow(Results::PageFetcher).to receive(:fetch).with(url).and_return(fetch_response)
      end

      context "and PageFetcher finds remaining keywords on full page" do
        let(:fetch_response) do
          instance_double(
            "PageFetcher::Response",
            status: :verified,
            text: "We require 5 years of Ruby on Rails experience",
            captcha_detected?: false
          )
        end

        it "merges evaluations and assigns verified status" do
          rank = subject
          expect(rank.relevance_score).to eq(200) # (2 * 100) - first group matched on page
          expect(rank.matched_keywords).to contain_exactly("senior", "ruby")
          expect(rank.verification_status).to eq("verified")
          expect(rank.valid?).to be true
        end
      end

      context "and PageFetcher encounters a Captcha" do
        let(:fetch_response) do
          instance_double(
            "PageFetcher::Response",
            status: :captcha,
            text: "",
            captcha_detected?: true
          )
        end

        it "returns unverified_captcha status and applies UNVERIFIED_PENALTY and FIRST_GROUP_PENALTY" do
          rank = subject
          # 1 matched group (100) - First group missing penalty (250) - Unverified penalty (50) = -200
          expect(rank.relevance_score).to eq(-200)
          expect(rank.matched_keywords).to contain_exactly("senior")
          expect(rank.verification_status).to eq("unverified_captcha")
          expect(rank.valid?).to be true
        end
      end

      context "and PageFetcher encounters an HTTP/Network error" do
        let(:fetch_response) do
          instance_double(
            "PageFetcher::Response",
            status: :error,
            text: "",
            captcha_detected?: false
          )
        end

        it "returns unverified_error status" do
          rank = subject
          expect(rank.verification_status).to eq("unverified_error")
          expect(rank.valid?).to be true
        end
      end
    end

    context "when no keywords match anywhere" do
      let(:snippet) { "Unrelated job description" }
      let(:fetch_response) do
        instance_double(
          "PageFetcher::Response",
          status: :verified,
          text: "Nothing relevant here",
          captcha_detected?: false
        )
      end

      before do
        allow(Results::PageFetcher).to receive(:fetch).with(url).and_return(fetch_response)
      end

      it "marks valid? as false" do
        rank = subject
        expect(rank.valid?).to be false
        expect(rank.matched_keywords).to be_empty
        # 0 matched groups - FIRST_GROUP_PENALTY (250) = -250
        expect(rank.relevance_score).to eq(-250)
      end
    end
  end
end
