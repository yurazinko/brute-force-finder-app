# frozen_string_literal: true

require "httparty"

module Results
  class StreamingPageFetcher
    MAX_BYTES = 1_048_576

    def self.fetch_and_match(url, keyword_groups: [])
      new(url, keyword_groups: keyword_groups).fetch
    end

    def initialize(url, keyword_groups: [])
      @url = url
      @keyword_groups = keyword_groups.map { |group| group.map(&:downcase) }
      @bytes_received = 0
    end

    def fetch
      html_content, captcha = stream_page_content
      return Results::PageFetcher::FetchResult.new(text: "", status: :captcha) if captcha

      parsed_text = extract_text_safely(html_content)
      Results::PageFetcher::FetchResult.new(text: parsed_text, status: :verified)
    rescue StandardError => e
      Rails.logger.warn("[StreamingPageFetcher] Failed to fetch #{@url}: #{e.message}")
      Results::PageFetcher::FetchResult.new(text: "", status: :error)
    end

    private

    def stream_page_content
      html_content = +""
      detected_captcha = false

      HTTParty.get(@url, headers: headers, timeout: 8, stream_body: true) do |chunk|
        @bytes_received += chunk.bytesize
        html_content << chunk

        if @bytes_received <= 32_768 && chunk.match?(Results::PageFetcher::CAPTCHA_REGEX)
          detected_captcha = true
          break
        end

        break if early_exit_possible?(html_content) || @bytes_received >= MAX_BYTES
      end

      [html_content, detected_captcha]
    end

    def early_exit_possible?(current_text)
      return false if @keyword_groups.empty?

      downcased = current_text.downcase
      @keyword_groups.all? do |group|
        group.any? { |kw| downcased.include?(kw) }
      end
    end

    def extract_text_safely(html)
      doc = Nokogiri::HTML5(html)
      doc.search("script, style, noscript, svg, header, footer, nav").remove

      doc.text.gsub(/\s+/, " ").strip.downcase
    end

    def headers
      {
        "User-Agent" => Results::PageFetcher::USER_AGENTS.sample,
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.9"
      }
    end
  end
end
