# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::StreamingPageFetcher, type: :service do
  let(:target_url) { "https://example.com/stream_job" }
  let(:keyword_groups) { [%w[ruby rails], %w[remote fulltime]] }

  describe ".fetch_and_match" do
    it "instantiates StreamingPageFetcher and calls #fetch" do
      fetcher = instance_double(described_class)
      expect(described_class).to receive(:new)
        .with(target_url, keyword_groups: keyword_groups)
        .and_return(fetcher)
      expect(fetcher).to receive(:fetch)

      described_class.fetch_and_match(target_url, keyword_groups: keyword_groups)
    end
  end

  describe "#fetch" do
    subject(:fetch) { described_class.new(target_url, keyword_groups: keyword_groups).fetch }

    before do
      allow(Resolv).to receive(:getaddresses).with("example.com").and_return(["93.184.216.34"])
    end

    context "when stream contains all keyword groups early" do
      let(:first_chunk) { "<html><body><h1>Senior Ruby Developer</h1><p>Position: Remote / Fulltime</p>" }
      let(:second_chunk) { "<div>#{'A' * 50_000}</div></body></html>" }

      before do
        stub_request(:get, target_url)
          .to_return(body: first_chunk + second_chunk)
      end

      it "triggers early exit after processing the first matching chunk" do
        result = fetch

        expect(result).to be_verified
        expect(result.text).to include("ruby", "remote")
      end
    end

    context "when ignored tags are present in stream" do
      let(:html_stream) do
        "<html><head><script>var keyword = 'ruby';</script><style>.remote { color: red; }</style></head>" \
          "<body><p>We need a Rails engineer with Fulltime commitment.</p></body></html>"
      end

      before do
        stub_request(:get, target_url).to_return(body: html_stream)
      end

      it "ignores text inside script, style, and nav tags" do
        result = fetch

        expect(result).to be_verified
        expect(result.text).not_to include("var keyword", "color: red")
        expect(result.text).to include("rails engineer with fulltime commitment")
      end
    end

    context "when CAPTCHA indicator is detected in initial chunk" do
      let(:captcha_chunk) { "<html><head><title>Just a moment...</title></head><body>cf-turnstile</body></html>" }

      before do
        stub_request(:get, target_url).to_return(body: captcha_chunk)
      end

      it "aborts stream and returns captcha FetchResult" do
        result = fetch

        expect(result).to be_captcha_detected
        expect(result.text).to be_empty
      end
    end

    context "when the server returns a CAPTCHA or challenge status" do
      [403, 429, 503].each do |status_code|
        it "returns a CAPTCHA status for HTTP #{status_code} even without a body marker" do
          stub_request(:get, target_url).to_return(status: status_code, body: "temporarily unavailable")

          expect(fetch).to be_captcha_detected
        end
      end
    end

    context "when Cloudflare returns a non-success response" do
      before do
        stub_request(:get, target_url)
          .to_return(status: 502, headers: { "Server" => "cloudflare" }, body: "challenge")
      end

      it "treats the response as a CAPTCHA challenge" do
        expect(fetch).to be_captcha_detected
      end
    end

    context "when a large first chunk contains a CAPTCHA marker" do
      before do
        body = "<html><body>#{'a' * 20_000} cf-turnstile#{'b' * 20_000}</body></html>"
        stub_request(:get, target_url).to_return(body: body)
      end

      it "checks the first 32 KB even when the first chunk exceeds that size" do
        result = fetch

        expect(result).to be_captcha_detected
        expect(result.text).to be_empty
      end
    end

    context "when the destination resolves to a private IP address" do
      before do
        allow(Resolv).to receive(:getaddresses).with("127.0.0.1").and_return(["127.0.0.1"])
      end

      it "blocks the request before making an HTTP call" do
        expect(HTTParty).not_to receive(:get)

        result = described_class.new("http://127.0.0.1/admin", keyword_groups: keyword_groups).fetch

        expect(result).to be_error
      end
    end

    context "when a safe result redirects to a private address" do
      let(:private_redirect) { "http://127.0.0.1:3000/admin" }

      before do
        allow(Resolv).to receive(:getaddresses).with("127.0.0.1").and_return(["127.0.0.1"])
        stub_request(:get, target_url).to_return(status: 302, headers: { "Location" => private_redirect })
      end

      it "rejects the redirect before requesting the private address" do
        result = fetch

        expect(result).to be_error
        expect(a_request(:get, private_redirect)).not_to have_been_made
      end
    end

    context "when following a safe redirect" do
      let(:redirect_url) { "https://example.com/redirected_page" }

      before do
        stub_request(:get, target_url).to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: "<html><body>Ruby Remote jobs</body></html>")
      end

      it "follows the redirect and extracts the final page" do
        result = fetch

        expect(result).to be_verified
        expect(result.text).to include("ruby remote jobs")
      end
    end

    context "when response exceeds MAX_BYTES limit" do
      let(:huge_chunk) { "<html><body>#{'a' * (described_class::MAX_BYTES + 500)}</body></html>" }

      before do
        stub_request(:get, target_url).to_return(body: huge_chunk)
      end

      it "aborts stream safely and keeps the buffered response within the size limit" do
        result = fetch

        expect(result).to be_verified
        expect(result.text.bytesize).to be <= described_class::MAX_BYTES
      end
    end

    context "when connection drops or fails" do
      before do
        stub_request(:get, target_url).to_raise(SocketError.new("Connection refused"))
      end

      it "handles exception, logs warning and returns error status" do
        expect(Rails.logger).to receive(:warn).with(/Failed to fetch/)

        result = fetch
        expect(result).to be_error
      end
    end
  end
end
