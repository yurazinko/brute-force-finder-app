# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::BatchPersister, type: :service do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user) }
  let(:prompt) { create(:prompt, search: search) }
  let!(:verified_result) do
    create(
      :result,
      search: search,
      url: "https://example.com/job/verified",
      verification_status: "verified",
      relevance_score: 93
    )
  end

  it "does not downgrade a verified result when a repeated scrape is only pending" do
    incoming = [{
      search_id: search.id,
      url: verified_result.url,
      url_hash: verified_result.url_hash,
      title: "Updated title",
      content: "Partial snippet",
      engine: "SearXNG",
      relevance_score: 25,
      verification_status: "pending",
      matched_keywords: ["ruby"]
    }]

    described_class.call(search, prompt, incoming)

    expect(verified_result.reload).to have_attributes(
      verification_status: "verified",
      relevance_score: 93,
      title: "Updated title"
    )
  end
end

RSpec.describe Results::BatchPersister, type: :service do
  describe "verification job scheduling" do
    let(:user) { create(:user) }
    let(:search) { create(:search, user: user) }
    let(:prompt) { create(:prompt, search: search) }
    let!(:pending_result) do
      create(
        :result, search: search, url: "https://example.com/job/pending",
                 verification_status: "pending"
      )
    end

    it "does not enqueue another verification job for an already pending result on every scrape" do
      incoming = [{
        url: pending_result.url, url_hash: pending_result.url_hash,
        title: "Updated title", content: "Updated snippet", engine: "SearXNG",
        verification_status: "pending", relevance_score: 0
      }]

      expect(ResultVerificationJob).not_to receive(:perform_async)
      described_class.call(search, prompt, incoming)
    end
  end
end
