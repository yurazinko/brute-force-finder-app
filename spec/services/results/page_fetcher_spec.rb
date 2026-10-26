# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::PageFetcher, type: :service do
  let(:target_url) { "https://example.com/job_offer" }

  describe ".fetch" do
    context "when keyword_groups are present" do
      let(:keyword_groups) { [%w[ruby rails]] }

      it "delegates execution to Results::StreamingPageFetcher" do
        expect(Results::StreamingPageFetcher).to receive(:fetch_and_match)
          .with(target_url, keyword_groups: keyword_groups)

        described_class.fetch(target_url, keyword_groups: keyword_groups)
      end
    end

    context "when keyword_groups are empty" do
      it "instantiates PageFetcher and calls #fetch" do
        fetcher_instance = instance_double(described_class)
        expect(described_class).to receive(:new).with(target_url).and_return(fetcher_instance)
        expect(fetcher_instance).to receive(:fetch)

        described_class.fetch(target_url)
      end
    end
  end

  describe "#fetch" do
    subject(:fetch) { described_class.new(target_url).fetch }

    let(:default_headers) { { "Content-Type" => "text/html" } }

    context "when request is successful and contains valid HTML" do
      let(:html_body) do
        <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Job Page</title>
              <style>body { color: red; }</style>
              <script>console.log("secret");</script>
            </head>
            <body>
              <nav>Navigation Bar</nav>
              <header>Header Content</header>
              <main>
                <h1>Senior Ruby Developer</h1>
                <p>We are looking for   a Rails expert!</p>
              </main>
              <footer>Footer Content</footer>
            </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, target_url)
          .to_return(status: 200, body: html_body, headers: default_headers)
      end

      it "returns a verified FetchResult with extracted and normalized text" do
        result = fetch

        expect(result).to be_verified
        expect(result.text).not_to include(
          "console.log", "body { color: red; }", "Navigation Bar", "Header Content", "Footer Content"
        )
        expect(result.text).to eq("job page senior ruby developer we are looking for a rails expert!")
      end
    end

    context "when page size exceeds MAX_BODY_SIZE" do
      let(:large_body) do
        padding = "a" * (described_class::MAX_BODY_SIZE + 1000)
        "<html><body><p>#{padding}</p></body></html>"
      end

      before do
        stub_request(:get, target_url)
          .to_return(status: 200, body: large_body, headers: default_headers)
      end

      it "slices the body before parsing DOM" do
        result = fetch
        expect(result).to be_verified
        expect(result.text.bytesize).to be <= described_class::MAX_BODY_SIZE
      end
    end

    context "when CAPTCHA is detected" do
      context "via HTTP status codes" do
        [403, 429, 503].each do |status_code|
          it "returns captcha status for HTTP #{status_code}" do
            stub_request(:get, target_url).to_return(status: status_code, body: "Access Blocked")

            result = fetch
            expect(result).to be_captcha_detected
            expect(result.text).to be_empty
          end
        end
      end

      context "via Cloudflare response headers" do
        it "returns captcha status when server is cloudflare and status is not 200" do
          stub_request(:get, target_url)
            .to_return(status: 502, headers: { "Server" => "cloudflare" }, body: "Error")

          result = fetch
          expect(result).to be_captcha_detected
        end
      end

      context "via body text indicator matching" do
        it "detects captcha indicators case-insensitively using CAPTCHA_REGEX" do
          stub_request(:get, target_url)
            .to_return(status: 200, body: "<html><body>Please Verify You Are A Human</body></html>")

          result = fetch
          expect(result).to be_captcha_detected
        end
      end
    end

    context "when network or standard HTTP error occurs" do
      before do
        stub_request(:get, target_url).to_timeout
      end

      it "logs warning and returns error FetchResult" do
        expect(Rails.logger).to receive(:warn).with(/Failed to fetch/)

        result = fetch
        expect(result).to be_error
        expect(result.text).to be_empty
      end
    end

    context "when SSRF security and IP validations apply" do
      let(:unsafe_urls) do
        [
          "http://127.0.0.1/admin",
          "http://localhost:3000/secret",
          "http://10.0.0.1/internal",
          "http://192.168.1.100/dashboard",
          "http://169.254.169.254/latest/meta-data/",
          "ftp://example.com/file"
        ]
      end

      it "blocks unsafe or private IP destinations and logs warning as error status" do
        unsafe_urls.each do |bad_url|
          fetcher = described_class.new(bad_url)
          result = fetcher.fetch

          expect(result).to be_error
          expect(result.text).to be_empty
        end
      end
    end

    context "when handling safe HTTP redirects" do
      let(:redirect_url) { "https://example.com/redirected_page" }

      before do
        stub_request(:get, target_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })

        stub_request(:get, redirect_url)
          .to_return(status: 200, body: "<html><body>Redirected Success Content</body></html>", headers: default_headers)
      end

      it "follows redirect chain safely up to the limit and fetches final content" do
        result = fetch
        expect(result).to be_verified
        expect(result.text).to include("redirected success content")
      end
    end

    context "when redirect chain exceeds maximum limit" do
      before do
        stub_request(:get, "https://example.com/job_offer")
          .to_return(status: 302, headers: { "Location" => "https://example.com/loop1" })
        stub_request(:get, "https://example.com/loop1")
          .to_return(status: 302, headers: { "Location" => "https://example.com/loop2" })
        stub_request(:get, "https://example.com/loop2")
          .to_return(status: 302, headers: { "Location" => "https://example.com/loop3" })
        stub_request(:get, "https://example.com/loop3")
          .to_return(status: 302, headers: { "Location" => "https://example.com/loop4" })
      end

      it "halts and returns error status" do
        result = fetch
        expect(result).to be_error
      end
    end
  end
end
