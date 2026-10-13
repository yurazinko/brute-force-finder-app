# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::DataTransformer, type: :model do
  describe ".process" do
    let(:search_id) { 42 }
    let(:user) { User.create!(email: "test@example.com", password: "password") }
    let(:category) { Category.create!(name: "General", user: user) }
    let(:target) { create(:target, domain: "example.com", category: category) }
    let(:prompt) { instance_double("Prompt", target: target, full_query_text: "ruby") }

    before do
      if target.present?
        search = Search.find_or_create_by!(id: search_id, user: user) do |s|
          s.title = "Ruby Search"
          s.query_conditions = "ruby"
        end
        Prompt.find_or_create_by!(search: search, target: target, full_query_text: "site:#{target.domain} ruby")
      end

      allow(Utils::UrlNormalizer).to receive(:normalize) do |url, target_configs: {}|
        domain = url.split("/").third&.delete_prefix("www.")

        keep_query = target_configs.any? do |target_domain, allow_query|
          (domain == target_domain || domain&.end_with?(".#{target_domain}")) && allow_query
        end

        keep_query ? url : url.split("?").first
      end

      allow(Utils::UrlNormalizer).to receive(:hash) do |url|
        "hash_of_#{url}"
      end

      stub_request(:get, /.*/).to_return(status: 200, body: "<html><body>ruby</body></html>", headers: {})
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
          url: "https://example.com/path",
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

    context "when target domain contains a specific subpath pattern" do
      let!(:pattern) { TargetPattern.create!(target: target, path_pattern: "/blog/*", is_active: true) }
      let(:raw_results) do
        [
          { "url" => "https://example.com/blog/ruby-post", "title" => "Blog Post" },
          { "url" => "https://example.com/shop/item-1", "title" => "Shop Item" }
        ]
      end

      it "only includes URLs matching the path prefix/pattern" do
        expect(processed_records.size).to eq(1)
        expect(processed_records.first[:url]).to eq("https://example.com/blog/ruby-post")
      end
    end

    context "when target domain includes protocol (http/https)" do
      let(:target) { create(:target, domain: "https://example.com", category: category) }

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
      let(:prompt) { instance_double("Prompt", target: nil, full_query_text: "ruby") }
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
      let(:target) { nil }
      let!(:query_target) { create(:target, domain: "query.com", allow_query_strings: true, category: category) }

      before do
        search = Search.find_or_create_by!(id: search_id, user: user) do |s|
          s.title = "Ruby Search"
          s.query_conditions = "ruby"
        end
        Prompt.find_or_create_by!(search: search, target: query_target, full_query_text: "site:query.com ruby")
      end

      let(:raw_results) do
        [
          { "url" => "https://example.com/p?q=1", "title" => "No Query" },
          { "url" => "https://query.com/p?q=2", "title" => "Keep Query" }
        ]
      end

      it "preserves query parameters only for allowed domains" do
        urls = processed_records.pluck(:url)
        expect(urls).to include("https://example.com/p")
        expect(urls).to include("https://query.com/p?q=2")
      end
    end

    context "when processing subdomains with allow_query_strings enabled" do
      let(:target) { create(:target, domain: "indeed.com", allow_query_strings: true, category: category) }
      let(:raw_results) do
        [
          { "url" => "https://pl.indeed.com/viewjob?jk=c632099926f119ae", "title" => "Job PL" },
          { "url" => "https://ca.indeed.com/viewjob?jk=a111222333b4455c", "title" => "Job CA" }
        ]
      end

      it "matches regional subdomains to the root target domain and keeps query strings" do
        expect(processed_records.size).to eq(2)
      end

      it "generates unique url_hashes for each job on regional subdomains" do
        hashes = processed_records.pluck(:url_hash)
        expect(hashes.first).to eq("hash_of_https://pl.indeed.com/viewjob?jk=c632099926f119ae")
        expect(hashes.last).to eq("hash_of_https://ca.indeed.com/viewjob?jk=a111222333b4455c")
        expect(hashes.first).not_to eq(hashes.last)
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
