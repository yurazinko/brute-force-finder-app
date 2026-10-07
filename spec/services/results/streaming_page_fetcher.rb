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

    context "when stream contains all keyword groups early" do
      let(:first_chunk) { "<html><body><h1>Senior Ruby Developer</h1><p>Position: Remote / Fulltime</p>" }
      let(:second_chunk) { "<div>#{'A' * 50_000}</div></body></html>" }

      before do
        stub_request(:get, target_url)
          .to_return(body: [first_chunk, second_chunk])
      end

      it "triggers early exit after processing the first matching chunk" do
        result = fetch

        expect(result).to be_verified
        expect(result.text).to include("ruby", "remote")
      end
    end

    context "when ignored tags are present in stream" do
      let(:html_stream) do
        [
          "<html><head><script>var keyword = 'ruby';</script><style>.remote { color: red; }</style></head>",
          "<body><p>We need a Rails engineer with Fulltime commitment.</p></body></html>"
        ]
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
        stub_request(:get, target_url).to_return(body: [captcha_chunk])
      end

      it "aborts stream and returns captcha FetchResult" do
        result = fetch

        expect(result).to be_captcha_detected
        expect(result.text).to be_empty
      end
    end

    context "when response exceeds MAX_BYTES limit" do
      let(:huge_chunk) { "a" * (described_class::MAX_BYTES + 500) }

      before do
        stub_request(:get, target_url).to_return(body: [huge_chunk])
      end

      it "aborts stream safely and returns partial normalized text" do
        result = fetch

        expect(result).to be_verified
        expect(result.text.bytesize).to be >= described_class::MAX_BYTES
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
