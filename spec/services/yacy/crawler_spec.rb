# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchEngines::Yacy::Api::Crawler do
  subject(:crawler_service) { described_class.new(query, options) }

  let(:query) { "https://uk.indeed.com/jobs" }
  let(:options) { {} }
  let(:instance_url) { "http://localhost:8090" }

  before do
    allow(crawler_service).to receive(:next_available_instance).and_return(instance_url)
    allow(crawler_service).to receive(:auth_credentials).and_return({ username: "admin", password: "yacy" })
  end

  describe "#build_crawler_params (via perform_request)" do
    let(:sent_body) do
      body = nil
      allow(described_class).to receive(:post) do |_url, opts|
        body = opts[:body]
        double(success?: true, code: 200)
      end
      crawler_service.execute
      body
    end

    describe "Regexp matching accuracy across edge cases" do
      let(:mustmatch_regex) { Regexp.new(sent_body["mustmatch"]) }

      context "with regional subdomain (Indeed case)" do
        let(:query) { "https://uk.indeed.com/q-ruby-jobs.html" }

        it "matches all subdomains of indeed.com but rejects other domains" do
          expect(sent_body.key?("range")).to be false

          # Positive matches
          expect("https://uk.indeed.com/viewjob?id=123").to match(mustmatch_regex)
          expect("https://pl.indeed.com/jobs").to match(mustmatch_regex)
          expect("http://indeed.com").to match(mustmatch_regex)
          expect("https://de.indeed.com:8443/path").to match(mustmatch_regex)

          # Negative matches
          expect("https://notindeed.com/jobs").not_to match(mustmatch_regex)
          expect("https://indeed.com.evil.com/phishing").not_to match(mustmatch_regex)
          expect("https://google.com").not_to match(mustmatch_regex)
        end
      end

      context "with multi-part TLDs (.co.uk, .com.au)" do
        let(:query) { "https://sub.blog.jobs.company.co.uk/search?q=test" }

        it "extracts the correct root domain and handles public suffixes" do
          expect("https://company.co.uk/about").to match(mustmatch_regex)
          expect("https://foo.company.co.uk/careers").to match(mustmatch_regex)
          expect("http://sub.blog.jobs.company.co.uk/item").to match(mustmatch_regex)

          # Negative matches
          expect("https://notcompany.co.uk").not_to match(mustmatch_regex)
          expect("https://co.uk").not_to match(mustmatch_regex)
          expect("https://othercompany.co.uk").not_to match(mustmatch_regex)
        end
      end

      context "with Australian TLD (.com.au)" do
        let(:query) { "http://foo.example.com.au/path" }

        it "correctly anchors to example.com.au" do
          expect("https://example.com.au").to match(mustmatch_regex)
          expect("https://bar.example.com.au/test").to match(mustmatch_regex)

          expect("https://notexample.com.au").not_to match(mustmatch_regex)
          expect("https://com.au").not_to match(mustmatch_regex)
        end
      end

      context "with Localhost" do
        let(:query) { "http://localhost:3000/test" }

        it "matches localhost on any port and path" do
          expect("http://localhost/").to match(mustmatch_regex)
          expect("http://localhost:3000/test").to match(mustmatch_regex)
          expect("https://localhost:8443/api").to match(mustmatch_regex)

          expect("https://localhost.com").not_to match(mustmatch_regex)
          expect("https://notlocalhost/").not_to match(mustmatch_regex)
        end
      end

      context "with IPv4 address" do
        let(:query) { "http://192.168.1.100:8080/path" }

        it "matches the full IPv4 host accurately" do
          expect("http://192.168.1.100/").to match(mustmatch_regex)
          expect("http://192.168.1.100:8080/path").to match(mustmatch_regex)

          expect("http://192.168.1.101/").not_to match(mustmatch_regex)
          expect("http://1192.168.1.100/").not_to match(mustmatch_regex)
        end
      end

      context "with IPv6 address" do
        let(:query) { "http://[::1]:8080/index.html" }

        it "handles IPv6 syntax correctly" do
          expect("http://[::1]/").to match(mustmatch_regex)
          expect("http://[::1]:8080/path").to match(mustmatch_regex)

          expect("http://[::2]/").not_to match(mustmatch_regex)
        end
      end

      context "when query is a malformed or invalid URL" do
        let(:query) { "ht%tp://invalid url example.com" }

        it "does not raise URI::InvalidURIError and falls back to catch-all pattern" do
          expect { sent_body }.not_to raise_error
          expect(sent_body["mustmatch"]).to eq(".*")
          expect("https://any-domain.com").to match(mustmatch_regex)
        end
      end

      context "when query is empty or nil" do
        let(:query) { nil }

        it "safely returns catch-all pattern" do
          expect(crawler_service.execute).to eq({ success: true, data: [] })
          expect(crawler_service.send(:extract_domain_pattern, query)).to eq(".*")
        end
      end

      context "when URL is provided without protocol (http/https)" do
        let(:query) { "de.indeed.com/viewjob" }

        it "prepends http:// for URI.parse and extracts domain pattern correctly" do
          expect("https://de.indeed.com/viewjob").to match(mustmatch_regex)
          expect("https://indeed.com").to match(mustmatch_regex)
        end
      end

      context "when :mustmatch option is explicitly provided" do
        let(:query) { "https://uk.indeed.com" }
        let(:options) { { mustmatch: ".*custom-pattern.*" } }

        it "prioritizes explicit mustmatch over auto-generated pattern" do
          expect(sent_body["mustmatch"]).to eq(".*custom-pattern.*")
        end
      end

      context "when :range option is explicitly set to 'domain'" do
        let(:options) { { range: "domain" } }

        it "sends range='domain', resets mustmatch to '.*' and appends cleanup options" do
          expect(sent_body["range"]).to eq("domain")
          expect(sent_body["mustmatch"]).to eq(".*")
          expect(sent_body["deleteold"]).to eq("age")
          expect(sent_body["deleteIfOlderNumber"]).to eq("14")
          expect(sent_body["deleteIfOlderUnit"]).to eq("day")
        end
      end
    end
  end
end
