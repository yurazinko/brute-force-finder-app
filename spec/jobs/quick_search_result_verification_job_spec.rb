# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuickSearchResultVerificationJob, type: :job do
  let(:token) { SecureRandom.hex(16) }
  let(:user_id) { nil }
  let(:query) { '"Ruby" "developer"' }
  let(:state) do
    {
      "token" => token,
      "user_id" => user_id,
      "query" => query,
      "verification_total_count" => 1,
      "verification_completed_count" => 0
    }
  end
  let(:attributes) do
    {
      "url" => "https://example.com/job/1",
      "url_hash" => "result-hash",
      "title" => "Ruby developer",
      "content" => "Ruby developer role",
      "engine" => "SearXNG",
      "status" => "unread",
      "relevance_score" => 50,
      "matched_keywords" => %w[Ruby],
      "verification_status" => "pending"
    }
  end

  before do
    allow(QuickSearch::Store).to receive_messages(
      fetch: state,
      result: attributes,
      update_result!: attributes.merge("verification_status" => "unverified_captcha"),
      complete_verification!: state.merge("status" => "completed")
    )
    allow(QuickSearch::Store).to receive(:update!).and_return(state)
    allow(QuickSearch::Broadcaster).to receive(:status)
    allow(QuickSearch::Broadcaster).to receive(:replace_result)
    allow(Results::StreamingPageFetcher).to receive(:fetch_and_match)
      .and_return(Results::PageFetcher::FetchResult.new(text: "", status: :captcha))
  end

  it "marks CAPTCHA results without trying to solve them and broadcasts the updated card" do
    described_class.new.perform(token, user_id, attributes.fetch("url_hash"))

    expect(QuickSearch::Store).to have_received(:update_result!).with(
      token,
      url_hash: "result-hash",
      attributes: hash_including(verification_status: "unverified_captcha")
    )
    expect(QuickSearch::Broadcaster).to have_received(:replace_result).with(token, an_instance_of(Result))
    expect(QuickSearch::Store).to have_received(:complete_verification!).with(token, url_hash: "result-hash")
  end
end
