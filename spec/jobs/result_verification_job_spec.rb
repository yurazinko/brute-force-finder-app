# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResultVerificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:search) { create(:search, query_conditions: "ruby rails", relevance_mode: "strict") }
  let(:result) do
    create(
      :result,
      search: search,
      url: "https://example.com/job/1",
      verification_status: "pending",
      matched_keywords: ["ruby"]
    )
  end

  let(:fetch_result) do
    instance_double(
      Results::PageFetcher::FetchResult,
      status: :verified,
      text: "full page text about ruby and rails development",
      captcha_detected?: false
    )
  end

  let(:rank_result) do
    instance_double(
      Results::RelevanceRanker::RankResult,
      relevance_score: 100,
      matched_keywords: ["rails"]
    )
  end

  before do
    allow(Results::DorkParser).to receive(:parse_groups).and_return([%w[ruby], %w[rails]])
    allow(Results::StreamingPageFetcher).to receive(:fetch_and_match).and_return(fetch_result)
    allow(Results::RelevanceRanker).to receive(:call).and_return(rank_result)
    allow(Rails.cache).to receive(:write).and_return(true)
  end

  describe "#perform" do
    context "when result does not exist" do
      it "returns silently without raising errors" do
        expect { described_class.new.perform(-1) }.not_to(change { Result.count })
      end
    end

    context "when result is already verified" do
      before { result.update!(verification_status: "verified") }

      it "skips verification and exits early" do
        expect(Results::StreamingPageFetcher).not_to receive(:fetch_and_match)
        described_class.new.perform(result.id)
      end
    end

    context "when domain is throttled" do
      before do
        allow(Rails.cache).to receive(:write)
          .with("domain_throttle:example.com", true, nx: true, expires_in: 3.seconds)
          .and_return(false)
      end

      it "reschedules the job using perform_in with jitter and does not fetch the page" do
        expect(described_class).to receive(:perform_in).with(be_between(3.seconds, 6.seconds), result.id)
        expect(Results::StreamingPageFetcher).not_to receive(:fetch_and_match)

        described_class.new.perform(result.id)
      end
    end

    context "when page fetch is successful" do
      it "passes the owning search's relevance mode to the ranker" do
        expect(Results::RelevanceRanker).to receive(:call).with(
          result,
          fetch_result.text,
          [%w[ruby], %w[rails]],
          result.url,
          strict_mode: true
        ).and_return(rank_result)

        described_class.new.perform(result.id)
      end

      it "updates result with merged keywords, normalized relevance score, and verified status" do
        described_class.new.perform(result.id)
        result.reload

        expect(result.verification_status).to eq("verified")
        expect(result.relevance_score).to eq(100)
        expect(result.matched_keywords).to contain_exactly("ruby", "rails")
      end

      it "attempts to acquire domain throttle lock atomically at the start" do
        expect(Rails.cache).to receive(:write)
          .with("domain_throttle:example.com", true, nx: true, expires_in: 3.seconds)
          .and_call_original

        described_class.new.perform(result.id)
      end
    end

    context "when page fetch encounters a CAPTCHA" do
      let(:fetch_result) do
        instance_double(
          Results::PageFetcher::FetchResult,
          status: :error,
          text: "",
          captcha_detected?: true
        )
      end

      it "marks the result as unverified and applies the benefit-of-the-doubt floor for a primary match" do
        described_class.new.perform(result.id)
        result.reload

        expect(result.verification_status).to eq("unverified_captcha")
        expect(result.relevance_score).to eq(Results::RelevanceRanker::CAPTCHA_SCORE_FLOOR)
      end

      it "does not boost a result when the primary group did not match" do
        result.update!(matched_keywords: ["rails"], relevance_score: -100)

        described_class.new.perform(result.id)

        expect(result.reload.relevance_score).to eq(-100)
      end

      it "does not let a primary-only CAPTCHA candidate bypass balanced mode's secondary-group requirement" do
        search.update!(relevance_mode: "balanced")
        result.update!(matched_keywords: ["ruby"], relevance_score: 0)

        described_class.new.perform(result.id)

        expect(result.reload.relevance_score).to eq(0)
      end

      it "keeps a balanced CAPTCHA candidate above the floor when primary and a later group matched" do
        search.update!(relevance_mode: "balanced")
        result.update!(matched_keywords: %w[ruby rails], relevance_score: 10)

        described_class.new.perform(result.id)

        expect(result.reload.relevance_score).to eq(Results::RelevanceRanker::CAPTCHA_SCORE_FLOOR)
      end
    end

    context "when page fetch encounters a network or generic error" do
      let(:fetch_result) do
        instance_double(
          Results::PageFetcher::FetchResult,
          status: :error,
          text: "",
          captcha_detected?: false
        )
      end

      it "updates verification_status to unverified_error without changing the score" do
        original_score = result.relevance_score
        described_class.new.perform(result.id)
        result.reload

        expect(result.verification_status).to eq("unverified_error")
        expect(result.relevance_score).to eq(original_score)
      end
    end
  end
end
