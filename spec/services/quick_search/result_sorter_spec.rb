# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuickSearch::ResultSorter, type: :service do
  it "sorts by score and puts CAPTCHA results after normal results" do
    results = [
      {
        "url_hash" => "captcha", "relevance_score" => 100, "matched_keywords" => %w[a b],
        "verification_status" => "unverified_captcha"
      },
      {
        "url_hash" => "low", "relevance_score" => 25, "matched_keywords" => ["a"],
        "verification_status" => "verified"
      },
      {
        "url_hash" => "high", "relevance_score" => 80, "matched_keywords" => %w[a b],
        "verification_status" => "pending"
      }
    ]

    expect(described_class.call(results).pluck("url_hash")).to eq(%w[high low captcha])
  end

  it "prefers more keyword matches when relevance scores are equal" do
    results = [
      {
        "url_hash" => "two-matches", "relevance_score" => 50, "matched_keywords" => %w[a b],
        "verification_status" => "verified"
      },
      {
        "url_hash" => "one-match", "relevance_score" => 50, "matched_keywords" => ["a"],
        "verification_status" => "verified"
      }
    ]

    expect(described_class.call(results).pluck("url_hash"))
      .to eq(%w[two-matches one-match])
  end
end
