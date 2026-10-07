# frozen_string_literal: true

require "httparty"

module Results
  class PageFetcher
    include HTTParty

    MAX_BODY_SIZE = 2 * 1024 * 1024

    CAPTCHA_INDICATORS = [
      "cf-challenge", "cf-turnstile", "g-recaptcha", "hcaptcha", "enable javascript", "cloudflare", "captcha",
      "ray id:", "just a moment...", "attention required!", "enable cookies", "performing security verification",
      "are you a human?", "verify you are a human", "please complete the security check",
      "security check required", "access denied", "you are being redirected"
    ].freeze

    CAPTCHA_REGEX = Regexp.new(
      CAPTCHA_INDICATORS.map { |i| Regexp.escape(i) }.join("|"),
      Regexp::IGNORECASE
    ).freeze

    USER_AGENTS = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
      "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0"
    ].freeze

    FetchResult = Struct.new(:text, :status, keyword_init: true) do
      def captcha_detected?
        status == :captcha
      end

      def error?
        status == :error
      end

      def verified?
        status == :verified
      end
    end

    def self.fetch(url, keyword_groups: [])
      if keyword_groups.present?
        Results::StreamingPageFetcher.fetch_and_match(url, keyword_groups: keyword_groups)
      else
        new(url).fetch
      end
    end

    def initialize(url)
      @url = url
    end

    def fetch
      response = HTTParty.get(@url, headers: headers, timeout: 8, follow_redirects: true, max_redirects: 3)
      body_text = response.body.to_s

      if captcha_detected?(response, body_text)
        FetchResult.new(text: "", status: :captcha)
      else
        clean_text = extract_and_normalize_text(body_text)
        FetchResult.new(text: clean_text, status: :verified)
      end
    rescue StandardError => e
      Rails.logger.warn("[PageFetcher] Failed to fetch #{@url}: #{e.message}")
      FetchResult.new(text: "", status: :error)
    end

    private

    def headers
      {
        "User-Agent" => USER_AGENTS.sample,
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.9",
        "Cache-Control" => "no-cache",
        "Referer" => "https://www.google.com/"
      }
    end

    def captcha_detected?(response, body_text)
      return true if [403, 429, 503].include?(response.code)
      return true if response.headers["server"]&.downcase&.include?("cloudflare") && response.code != 200

      body_text.match?(CAPTCHA_REGEX)
    end

    def extract_and_normalize_text(html)
      processable_html = html.bytesize > MAX_BODY_SIZE ? html.byteslice(0, MAX_BODY_SIZE) : html

      doc = Nokogiri::HTML(processable_html)
      doc.xpath("//script|//style|//noscript|//svg|//header|//footer|//nav").remove

      text = doc.text
      text.gsub!(/\s+/, " ")
      text.strip!
      text.downcase!
      text
    end
  end
end
