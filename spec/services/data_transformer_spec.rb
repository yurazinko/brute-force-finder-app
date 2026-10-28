# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::DataTransformer, type: :model do
  describe ".process" do
    let(:search_id) { 42 }
    let(:user) { User.create!(username: "test@example.com", password: "password") }
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

      stub_request(:get, /.*/).to_return(status: 200, body: "<html><body>ruby</body></html>", headers: {})
      allow(Resolv).to receive(:getaddress).and_return("8.8.8.8")
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
          { "url" => "HTTPS://WWW.EXAMPLE.COM/ruby-page-one?utm_source=twitter", "title" => "Ruby Exact Match", "content" => "Ruby Text 1" },
          { "url" => "https://sub.example.com/ruby-page-two", "title" => "Ruby Subdomain Match", "content" => "Ruby Text 2" }
        ]
      end

      it "successfully transforms and normalizes matching records" do
        expect(processed_records.size).to eq(2)
      end

      it "preserves path case while downcasing scheme/domain and stripping www and default queries" do
        first_record = processed_records.find { |r| r[:title] == "Ruby Exact Match" }

        expect(first_record).to include(
          search_id: search_id,
          url: "https://example.com/ruby-page-one", # query вилучено за замовчуванням, www прибрано, домен у нижньому регістрі
          title: "Ruby Exact Match",
          content: "Ruby Text 1"
        )
        expect(first_record[:url_hash]).to eq(Utils::UrlNormalizer.hash("https://example.com/ruby-page-one"))
        expect(first_record[:created_at]).to be_a(Time)
        expect(first_record[:updated_at]).to be_a(Time)
      end
    end

    context "when deduplicating www and non-www URLs via real UrlNormalizer" do
      let(:raw_results) do
        [
          { "url" => "https://www.example.com/jobs/ruby", "title" => "Job WWW" },
          { "url" => "https://example.com/jobs/ruby", "title" => "Job Plain" }
        ]
      end

      it "generates identical url_hashes for www and non-www variants pointing to the same resource" do
        hashes = processed_records.pluck(:url_hash)
        expect(hashes.size).to eq(2)
        expect(hashes.first).to eq(hashes.last)
      end
    end

    context "when paths differ only by case (case-sensitivity edge case)" do
      let(:raw_results) do
        [
          { "url" => "https://example.com/Jobs/Ruby", "title" => "Upper Path" },
          { "url" => "https://example.com/jobs/ruby", "title" => "Lower Path" }
        ]
      end

      it "treats case-sensitive paths as distinct records with different hashes" do
        urls = processed_records.pluck(:url)
        hashes = processed_records.pluck(:url_hash)

        expect(urls).to include("https://example.com/Jobs/Ruby")
        expect(urls).to include("https://example.com/jobs/ruby")
        expect(hashes.first).not_to eq(hashes.last)
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
          { "url" => "https://example.com/p?q=1", "title" => "No Query Target Config" },
          { "url" => "https://query.com/p?q=2", "title" => "Keep Query Target Config" }
        ]
      end

      it "preserves query parameters only for allowed domains configured on targets" do
        urls = processed_records.pluck(:url)
        expect(urls).to include("https://example.com/p")
        expect(urls).to include("https://query.com/p?q=2")
      end
    end

    context "when processing regional subdomains with allow_query_strings enabled" do
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
        expect(hashes.first).to eq(Utils::UrlNormalizer.hash("https://pl.indeed.com/viewjob?jk=c632099926f119ae"))
        expect(hashes.last).to eq(Utils::UrlNormalizer.hash("https://ca.indeed.com/viewjob?jk=a111222333b4455c"))
        expect(hashes.first).not_to eq(hashes.last)
      end
    end
  end
end
