# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::Importers::ResultImporter do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user) }
  let(:id_maps) { { searches: { "source-search" => search.id }, targets: {} } }
  let(:timestamp) { Time.current.iso8601 }
  let(:records) do
    [
      { "id" => 1, "search_id" => "source-search", "url" => "https://example.com/job",
        "url_hash" => "same-hash", "title" => "Old title", "status" => "unread",
        "verification_status" => "pending", "created_at" => timestamp, "updated_at" => timestamp },
      { "id" => 2, "search_id" => "source-search", "url" => "https://example.com/job",
        "url_hash" => "same-hash", "title" => "Latest title", "status" => "watched",
        "acknowledged" => true, "verification_status" => "verified", "created_at" => timestamp,
        "updated_at" => timestamp }
    ]
  end

  it "collapses duplicate conflict keys in the same backup and keeps the last row" do
    expect do
      described_class.new(records, user.id, id_maps).call
    end.to change(search.results, :count).by(1)

    result = search.results.find_by!(url_hash: "same-hash")
    expect(result.title).to eq("Latest title")
    expect(result.status).to eq("watched")
    expect(result.acknowledged).to be(true)
    expect(result.verification_status).to eq("verified")
  end

  it "is idempotent when the same rows are upserted again" do
    described_class.new(records, user.id, id_maps).call
    expect { described_class.new(records, user.id, id_maps).call }.not_to change(search.results, :count)
  end

  it "falls back to the application URL-hash function for legacy rows without a hash" do
    legacy = [records.first.except("url_hash")]
    described_class.new(legacy, user.id, id_maps).call
    result = search.results.sole
    expect(result.url_hash).to eq(Utils::UrlNormalizer.hash("https://example.com/job"))
  end
end
