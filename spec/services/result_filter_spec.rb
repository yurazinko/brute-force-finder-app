# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::ResultFilter, type: :service do
  let(:target) { double("Target", domain: "example.com") }
  let(:prompt) { double("Prompt", target: target, full_query_text: 'site:example.com (ruby OR "ruby on rails")') }
  let(:target_configs) { { "example.com" => false } }

  let(:valid_result) do
    {
      "url" => "https://example.com/jobs/dev",
      "title" => "Senior Developer",
      "content" => "We are looking for an experienced software engineer."
    }
  end

  subject { described_class.new(valid_result, prompt, target_configs) }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  describe "#valid?" do
    context "when URL is blank" do
      let(:valid_result) { { "url" => "", "title" => "Test", "content" => "Test" } }

      it "returns false" do
        expect(subject.valid?).to be false
      end
    end

    context "when URL does not match the target domain" do
      let(:valid_result) { { "url" => "https://other-domain.com/job", "title" => "Ruby", "content" => "Ruby" } }

      it "returns false" do
        expect(subject.valid?).to be false
      end
    end

    context "when keyword is present in snippet" do
      let(:valid_result) do
        {
          "url" => "https://example.com/jobs/ruby-developer",
          "title" => "Ruby Engineer",
          "content" => "Some description"
        }
      end

      it "returns true without making an HTTP request" do
        expect(subject.valid?).to be true
        expect(WebMock).not_to have_requested(:get, /.*/)
      end
    end

    context "when keywords are present on the page" do
      let(:html_body) { "<html><body><h1>Welcome</h1><p>We work with Ruby on Rails here!</p></body></html>" }

      before do
        stub_request(:get, valid_result["url"])
          .with(headers: { "Cache-Control" => "no-cache" })
          .to_return(status: 200, body: html_body, headers: {})
      end

      it "fetches page via WebMock stub and returns true" do
        expect(subject.valid?).to be true
      end
    end

    context "when keywords are missing both in snippet and page" do
      let(:html_body) { "<html><body><h1>Welcome</h1><p>We work only with Python and Go.</p></body></html>" }

      before do
        stub_request(:get, valid_result["url"])
          .with(headers: { "Cache-Control" => "no-cache" })
          .to_return(status: 200, body: html_body, headers: {})
      end

      it "returns false" do
        expect(subject.valid?).to be false
      end
    end

    context "when challenge protection is triggered (Captcha / Cloudflare)" do
      context "when status code is 403, 429, or 503" do
        before do
          stub_request(:get, valid_result["url"])
            .to_return(status: 403, body: "Forbidden")
        end

        it "returns true to allow manual verification" do
          expect(subject.valid?).to be true
        end
      end

      context "when body contains captcha indicators" do
        let(:html_body) { "<html><body>Just a moment... Enable cookies to continue</body></html>" }

        before do
          stub_request(:get, valid_result["url"])
            .to_return(status: 200, body: html_body, headers: { "Server" => "cloudflare" })
        end

        it "detects captcha and returns true" do
          expect(subject.valid?).to be true
        end
      end
    end

    context "when request raises a network error" do
      before do
        stub_request(:get, valid_result["url"]).to_timeout
      end

      it "logs warning and returns true" do
        expect(Rails.logger).to receive(:warn).with(/Failed to fetch/)
        expect(subject.valid?).to be true
      end
    end
  end

  describe "private methods" do
    describe "#extract_keywords_from_prompt" do
      it "extracts phrases and standalone words" do
        query = 'site:apply.workable.com tld:io (ruby OR "ruby on rails") /date (worldwide OR anywhere)'
        keywords = subject.send(:extract_keywords_from_prompt, query)

        expect(keywords).to match_array(["ruby on rails", "ruby", "worldwide", "anywhere"])
      end
    end

    describe "#url_matches_target?" do
      let(:target) { double("Target", domain: "example.com/careers") }

      it "returns true for matched subpaths" do
        filter = described_class.new({ "url" => "https://example.com/careers/ruby-dev" }, prompt, target_configs)
        expect(filter.send(:url_matches_target?)).to be true
      end

      it "returns false for unmatched paths" do
        filter = described_class.new({ "url" => "https://example.com/about" }, prompt, target_configs)
        expect(filter.send(:url_matches_target?)).to be false
      end
    end
  end
end
