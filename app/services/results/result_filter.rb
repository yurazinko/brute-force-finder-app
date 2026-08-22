# frozen_string_literal: true

require "httparty"

module Results
  class ResultFilter
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

    def initialize(result, prompt, target_configs)
      @result = result
      @prompt = prompt
      @target_configs = target_configs
      @url = result["url"]
      @keywords = extract_keywords_from_prompt(prompt&.full_query_text)
    end

    def valid?
      return false if @url.blank?
      return false unless url_matches_target?

      return true if matches_keywords?(snippet_text)

      fetch_and_verify_page
    end

    private

    def snippet_text
      [@result["url"], @result["title"], @result["content"]].compact.join(" ")
    end

    def fetch_and_verify_page
      response = fetch_page
      return false unless response

      body_text = response.body.to_s

      return true if captcha_detected?(response, body_text)

      clean_text = extract_plain_text(body_text)
      matches_keywords?(clean_text)
    rescue StandardError => e
      Rails.logger.warn("[ResultFilter] Failed to fetch #{@url}: #{e.message}")
      true
    end

    def fetch_page
      headers = {
        "User-Agent" => USER_AGENTS.sample,
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.9",
        "Cache-Control" => "no-cache"
      }

      HTTParty.get(
        @url,
        headers: headers,
        timeout: 8,
        follow_redirects: true,
        max_redirects: 3
      )
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

    def matches_keywords?(text)
      return true if @keywords.empty?

      downcased_text = text.downcase
      @keywords.any? { |kw| downcased_text.include?(kw.downcase) }
    end

    def extract_keywords_from_prompt(query_text)
      return [] if query_text.blank?

      text = query_text.dup
      text.gsub!(/\b(site|tld|from):[^\s]+/i, "")
      text.gsub!(%r{/\w+}, "")

      quoted_phrases = text.scan(/"([^"]+)"/).flatten
      clean_unquoted = text.gsub(/"[^"]+"/, "").gsub(/[()]/, " ").gsub(/\b(OR|AND|NOT)\b/, " ")
      unquoted_words = clean_unquoted.split(/\s+/).reject { |w| w.length < 2 }

      (quoted_phrases + unquoted_words).uniq
    end

    def url_matches_target?
      target = @prompt&.target
      return true if target.blank? || target.domain.blank?

      target_str = target.domain.to_s.sub(%r{\Ahttps?://}, "").sub(DataTransformer::WWW_PREFIX, "")
      target_host, target_path = target_str.split("/", 2)

      uri = URI.parse(@url)
      result_host = uri.host&.sub(DataTransformer::WWW_PREFIX, "")

      return false unless host_matches?(result_host, target_host)

      path_matches?(uri.path, target_path)
    rescue URI::InvalidURIError
      false
    end

    def host_matches?(result_host, target_host)
      return false if result_host.blank?

      result_host == target_host || result_host.end_with?(".#{target_host}")
    end

    def path_matches?(result_path, target_path)
      return true if target_path.blank?

      result_path.to_s.delete_prefix("/").start_with?(target_path)
    end
  end
end
