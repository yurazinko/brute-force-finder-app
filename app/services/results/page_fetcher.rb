# frozen_string_literal: true

require "uri"

module Results
  class PageFetcher
    MAX_BODY_SIZE = 2 * 1024 * 1024

    CAPTCHA_INDICATORS = [
      "cf-challenge", "cf-chl-", "cf-turnstile", "cf-turnstile-response",
      "g-recaptcha", "hcaptcha", "h-captcha", "just a moment...",
      "are you a human?", "verify you are a human", "please complete the security check",
      "security check required", "captcha challenge"
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
      def captcha_detected? = status == :captcha
      def error? = status == :error
      def verified? = status == :verified
    end

    def self.fetch(url, keyword_groups: [])
      new(url).fetch(keyword_groups: keyword_groups)
    end

    def initialize(url)
      @url = url
    end

    def fetch(keyword_groups: [])
      # One transport path for every page: streaming, bounded response body,
      # validated redirects, Tor adapter and a single overall deadline.
      Results::StreamingPageFetcher.fetch_and_match(@url, keyword_groups: keyword_groups)
    end

    private

    def fetch_with_safe_redirects(current_url, limit = 3)
      raise "Too many HTTP redirects or unsafe redirect chain" if limit <= 0
      raise "SSRF blocked: unsafe URL destination (#{current_url})" unless Results::SafeUrlValidator.safe?(current_url)

      uri = URI.parse(current_url)
      response = Results::TorHttpClient.get(uri, headers: headers, timeout: 8, follow_redirects: false)

      if response.code.in?([301, 302, 303, 307, 308]) && response.headers["location"]
        redirect_url = URI.join(uri, response.headers["location"]).to_s
        return fetch_with_safe_redirects(redirect_url, limit - 1)
      end

      response
    end

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
