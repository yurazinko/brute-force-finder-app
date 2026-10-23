# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResultVerificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:search) { create(:search, query_conditions: "ruby, rails") }
  let(:result) { create(:result, search: search, url: "https://example.com/job/1", verification_status: "pending", matched_keywords: ["ruby"]) }

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
      relevance_score: 200,
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
        expect do
          described_class.new.perform(-1)
        end.not_to(change { Result.count })
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
        # Симулюємо зайнятість домену (write з nx: true повертає false, бо ключ вже існує)
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

    context "when page fetch is successful and verified" do
      it "updates result with merged keywords, relevance score, and verified status" do
        expect do
          described_class.new.perform(result.id)
          result.reload
        end.to change { result.verification_status }.from("pending").to("verified")

        expect(result.relevance_score).to eq(200)
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

      it "updates verification_status to unverified_captcha" do
        described_class.new.perform(result.id)
        result.reload

        expect(result.verification_status).to eq("unverified_captcha")
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

      it "updates verification_status to unverified_error" do
        described_class.new.perform(result.id)
        result.reload

        expect(result.verification_status).to eq("unverified_error")
      end
    end
  end
end
