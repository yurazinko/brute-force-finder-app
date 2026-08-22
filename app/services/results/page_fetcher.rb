# frozen_string_literal: true

# app/services/results/page_fetcher.rb
module Results
  class PageFetcher
    include HTTParty

    CAPTCHA_INDICATORS = [
      "cf-challenge", "cf-turnstile", "g-recaptcha", "hcaptcha",
      "ray id:", "just a moment...", "attention required!", "enable cookies"
    ].freeze

    USER_AGENTS = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
      "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0"
    ].freeze

    FetchResult = Struct.new(:text, :captcha_detected?, :error?, keyword_init: true)

    def self.fetch(url)
      new(url).fetch
    end

    def initialize(url)
      @url = url
    end

    def fetch
      response = HTTParty.get(@url, headers: headers, timeout: 8, follow_redirects: true, max_redirects: 3)
      body_text = response.body.to_s

      if captcha_detected?(response, body_text)
        FetchResult.new(text: "", captcha_detected?: true, error?: false)
      else
        clean_text = extract_plain_text(body_text)
        FetchResult.new(text: clean_text, captcha_detected?: false, error?: false)
      end
    rescue StandardError => e
      Rails.logger.warn("[PageFetcher] Failed to fetch #{@url}: #{e.message}")
      FetchResult.new(text: "", captcha_detected?: false, error?: true)
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

      downcased_body = body_text.downcase
      CAPTCHA_INDICATORS.any? { |indicator| downcased_body.include?(indicator) }
    end

    def extract_plain_text(html)
      doc = Nokogiri::HTML(html)
      doc.xpath("//script|//style|//noscript|//svg|//header|//footer|//nav").remove
      doc.text.squeeze(" \n\r\t")
    end
  end
end
