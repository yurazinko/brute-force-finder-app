# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::QuickSearchResultsImporter, type: :service do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user, title: "Imported campaign", query_conditions: "ruby") }
  let(:token) { "a" * 32 }
  let(:quick_search) { { "status" => "completed", "user_id" => nil } }
  let(:records) do
    [
      {
        "url" => "https://example.com/job",
        "url_hash" => "job-hash",
        "title" => "Ruby developer",
        "content" => "Ruby role",
        "engine" => "SearXNG",
        "status" => "watched",
        "acknowledged" => true,
        "relevance_score" => 88,
        "matched_keywords" => ["ruby"],
        "verification_status" => "verified",
        "created_at" => 1.hour.ago.iso8601
      }
    ]
  end

  before do
    allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search)
    allow(QuickSearch::Store).to receive(:results).with(token).and_return(records)
  end

  it "copies only supported result fields and preserves the transient read state" do
    expect do
      expect(described_class.new(search: search, token: token).call).to eq(1)
    end.to change(search.results, :count).by(1)

    imported = search.results.find_by!(url_hash: "job-hash")
    expect(imported.status).to eq("watched")
    expect(imported.acknowledged).to be(true)
    expect(imported.relevance_score).to eq(88)
    expect(imported.matched_keywords).to eq(["ruby"])
    expect(imported.verification_status).to eq("verified")
  end

  it "does not import a quick search that has not completed" do
    allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search.merge("status" => "verifying"))

    expect do
      expect(described_class.new(search: search, token: token).call).to be_nil
    end.not_to change(search.results, :count)
  end

  it "does not import results owned by a different signed-in user" do
    allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search.merge("user_id" => user.id + 1))

    expect do
      expect(described_class.new(search: search, token: token).call).to be_nil
    end.not_to change(search.results, :count)
  end
end
