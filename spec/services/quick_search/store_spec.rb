# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuickSearch::Store, type: :service do
  let(:token) { "a" * 32 }
  let(:redis) { double("Sidekiq Redis client") }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis)
  end

  describe ".update!" do
    it "sends EVAL using RedisClient's flattened command argument format" do
      response = { "status" => "processing", "message" => "Searching…" }

      expect(redis).to receive(:call).with(
        "EVAL",
        described_class::Scripts::UPDATE,
        "1",
        "quick_search:v1:#{token}:data",
        JSON.generate("status" => "processing", "message" => "Searching…"),
        described_class::TTL.to_s
      ).and_return(JSON.generate(response))

      expect(described_class.update!(token, status: "processing", message: "Searching…")).to eq(response)
    end
  end

  describe ".complete_verification!" do
    it "passes both Redis keys and the TTL as scalar EVAL arguments" do
      response = { "status" => "verifying", "verification_pending_count" => 1 }
      url_hash = "result-hash"

      expect(redis).to receive(:call).with(
        "EVAL",
        described_class::Scripts::COMPLETE_VERIFICATION,
        "2",
        "quick_search:v1:#{token}:data",
        "quick_search:v1:#{token}:verification:#{url_hash}",
        described_class::TTL.to_s
      ).and_return(JSON.generate(response))

      expect(described_class.complete_verification!(token, url_hash: url_hash)).to eq(response)
    end
  end

  describe ".append_results" do
    it "uses an atomic EVAL that refuses to recreate results after the session was cleared" do
      records = [{ "url_hash" => "hash-1", "title" => "Rails job" }]
      serialized = records.map { |record| record.slice(*described_class::RESULT_FIELDS).to_json }

      expect(redis).to receive(:call).with(
        "EVAL",
        described_class::Scripts::APPEND_RESULTS,
        "2",
        "quick_search:v1:#{token}:data",
        "quick_search:v1:#{token}:results",
        described_class::TTL.to_s,
        *serialized
      ).and_return(1)

      described_class.append_results(token, records)
    end
  end

  describe ".clear!" do
    it "marks the search cleared and deletes its result and verification keys" do
      allow(described_class).to receive(:results).with(token).and_return([{ "url_hash" => "hash-1" }])
      allow(described_class).to receive(:update!).with(
        token,
        status: "cleared",
        active_engine: nil,
        message: "Quick Search results cleared.",
        results_count: 0,
        verification_pending_count: 0
      ).and_return({ "status" => "cleared" })

      expect(redis).to receive(:del).with(
        "quick_search:v1:#{token}:results",
        "quick_search:v1:#{token}:verification:hash-1"
      )

      expect(described_class.clear!(token)).to be(true)
    end
  end
end
