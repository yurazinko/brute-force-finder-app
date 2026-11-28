# frozen_string_literal: true

module Results
  class PageFetcher
    MAX_BODY_SIZE = 2 * 1024 * 1024

    CAPTCHA_INDICATORS = [
      "cf-challenge", "cf-chl-", "cf-turnstile", "cf-turnstile-response",
      "g-recaptcha", "hcaptcha", "h-captcha", "captcha challenge",
      "just a moment...", "attention required!", "are you a human?",
      "verify you are a human", "please complete the security check",
      "security check required"
    ].freeze

    CAPTCHA_REGEX = Regexp.new(
      CAPTCHA_INDICATORS.map { |indicator| Regexp.escape(indicator) }.join("|"),
      Regexp::IGNORECASE
    ).freeze

    USER_AGENTS = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
        "(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
      "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0"
    ].freeze

    FetchResult = Struct.new(:text, :status, keyword_init: true) do
      def captcha_detected? = status == :captcha
      def error? = status == :error
      def verified? = status == :verified
    end

    def self.fetch(url, keyword_groups: [])
      Results::StreamingPageFetcher.fetch_and_match(url, keyword_groups: keyword_groups)
    end

    def initialize(url)
      @url = url
    end

    def fetch(keyword_groups: [])
      self.class.fetch(@url, keyword_groups: keyword_groups)
    end
  end
end
