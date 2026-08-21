# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::DataTransformer, type: :model do
  describe ".process" do
    let(:search_id) { 42 }
    let(:target_domain) { "example.com" }
    let(:target) { instance_double("Target", domain: target_domain) }
    let(:prompt) { instance_double("Prompt", target: target) }

    before do
      # Mock the URL normalizer behavior
      allow(Utils::UrlNormalizer).to receive(:normalize) do |url, keep_query:|
        keep_query ? url : url.split("?").first
      end

      allow(Utils::UrlNormalizer).to receive(:hash) do |url|
        "hash_of_#{url}"
      end

      # Stub the database query to avoid database dependence
      allow(Target).to receive_message_chain(:joins, :where, :pluck, :to_h)
        .and_return({ "example.com" => false, "query.com" => true })
    end

    subject(:processed_records) { described_class.process(search_id, raw_results, prompt) }

    context "when raw_results is empty or nil" do
      let(:raw_results) { nil }

      it "returns an empty array" do
        expect(processed_records).to eq([])
      end
    end

    context "when results contain invalid or blank URLs" do
      let(:raw_results) do
        [
          { "url" => "", "title" => "Empty" },
          { "url" => "not a valid url", "title" => "Invalid" }
        ]
      end

      it "ignores them and returns an empty array" do
        expect(processed_records).to eq([])
      end
    end

    context "when result domains do not match the target" do
      let(:raw_results) do
        [
          { "url" => "https://wrongdomain.com/page", "title" => "Wrong" }
        ]
      end

      it "filters them out" do
        expect(processed_records).to eq([])
      end
    end

    context "when domains match the target" do
      let(:raw_results) do
        [
          { "url" => "https://example.com/path?abc=123", "title" => "Exact Match", "content" => "Text 1" },
          { "url" => "https://sub.example.com/path", "title" => "Subdomain Match", "content" => "Text 2" },
          { "url" => "https://www.example.com/path", "title" => "WWW Match", "content" => "Text 3" }
        ]
      end

      it "successfully transforms all matching records" do
        expect(processed_records.size).to eq(3)
      end

      it "builds the correct hash structure for each record" do
        first_record = processed_records.first

        expect(first_record).to include(
          search_id: search_id,
          url: "https://example.com/path", # Query strings are stripped because example.com is false
          url_hash: "hash_of_https://example.com/path",
          title: "Exact Match",
          content: "Text 1"
        )
        expect(first_record[:created_at]).to be_a(Time)
        expect(first_record[:updated_at]).to be_a(Time)
      end
    end

    context "when target is blank" do
      let(:target) { nil }
      let(:raw_results) do
        [
          { "url" => "https://anydomain.com/page", "title" => "Any", "content" => "Content" }
        ]
      end

      it "allows any domain without target domain filtering" do
        expect(processed_records.size).to eq(1)
        expect(processed_records.first[:url]).to eq("https://anydomain.com/page")
      end
    end

    context "when target domain contains a specific subpath" do
      let(:target_domain) { "example.com/blog" }

      let(:raw_results) do
        [
          { "url" => "https://example.com/blog/ruby-post", "title" => "Blog Post" },
          { "url" => "https://example.com/shop/item-1", "title" => "Shop Item" }
        ]
      end

      it "only includes URLs matching the path prefix" do
        expect(processed_records.size).to eq(1)
        expect(processed_records.first[:url]).to eq("https://example.com/blog/ruby-post")
      end
    end

    context "when target domain includes protocol (http/https)" do
      let(:target_domain) { "https://example.com" }

      let(:raw_results) do
        [
          { "url" => "https://example.com/page", "title" => "Page" }
        ]
      end

      it "correctly strips protocol from target domain and matches URL" do
        expect(processed_records.size).to eq(1)
      end
    end

    context "when result contains malformed URL raising URI::InvalidURIError" do
      let(:raw_results) do
        [
          { "url" => "http://[invalid_host]:8080/path", "title" => "Bad URI" }
        ]
      end

      it "handles URI::InvalidURIError gracefully and ignores the record" do
        expect { processed_records }.not_to raise_error
        expect(processed_records).to eq([])
      end
    end

    context "when prompt is nil" do
      let(:prompt) { instance_double("Prompt", target: nil) }
      let(:raw_results) do
        [
          { "url" => "https://anydomain.com/page", "title" => "Any", "content" => "Content" }
        ]
      end

      it "allows any domain without target domain filtering" do
        expect(processed_records.size).to eq(1)
        expect(processed_records.first[:url]).to eq("https://anydomain.com/page")
      end
    end

    context "checking keep_query (allow_query_strings) logic" do
      let(:target) { nil } # Disable domain filtering for this specific test
      let(:raw_results) do
        [
          { "url" => "https://example.com/p?q=1", "title" => "No Query" },
          { "url" => "https://query.com/p?q=2", "title" => "Keep Query" }
        ]
      end

      it "passes the correct keep_query flag to the normalizer based on domain config" do
        expect(Utils::UrlNormalizer).to receive(:normalize).with("https://example.com/p?q=1", keep_query: false)
        expect(Utils::UrlNormalizer).to receive(:normalize).with("https://query.com/p?q=2", keep_query: true)

        processed_records
      end

      it "preserves query parameters only for allowed domains" do
        urls = processed_records.pluck(:url)
        expect(urls).to include("https://example.com/p") # Query removed
        expect(urls).to include("https://query.com/p?q=2") # Query preserved
      end
    end

    context "when normalizer returns a blank string" do
      let(:raw_results) do
        [
          { "url" => "https://example.com/bad-page", "title" => "Bad" }
        ]
      end

      before do
        allow(Utils::UrlNormalizer).to receive(:normalize).and_return("")
      end

      it "ignores the result" do
        expect(processed_records).to eq([])
      end
    end
  end
end
