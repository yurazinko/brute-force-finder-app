# frozen_string_literal: true

require "httparty"
require "ipaddr"
require "resolv"
require "uri"

module Results
  class StreamingPageFetcher
    MAX_BYTES = 1_048_576
    CAPTCHA_PREFIX_BYTES = 32_768
    EARLY_MATCH_CHECK_INTERVAL = 16_384
    MAX_REDIRECTS = 3

    def self.fetch_and_match(url, keyword_groups: [])
      new(url, keyword_groups: keyword_groups).fetch
    end

    def initialize(url, keyword_groups: [])
      @url = url
      @keyword_groups = keyword_groups.map { |group| group.map(&:downcase) }
    end

    def fetch
      html_content, captcha = stream_page_content(@url)
      return Results::PageFetcher::FetchResult.new(text: "", status: :captcha) if captcha

      parsed_text = extract_text_safely(html_content)
      Results::PageFetcher::FetchResult.new(text: parsed_text, status: :verified)
    rescue StandardError => e
      Rails.logger.warn("[StreamingPageFetcher] Failed to fetch #{@url}: #{e.message}")
      Results::PageFetcher::FetchResult.new(text: "", status: :error)
    end

    private

    def stream_page_content(current_url, redirects_remaining = MAX_REDIRECTS)
      raise "Too many HTTP redirects" if redirects_remaining.negative?
      raise "SSRF blocked: unsafe URL destination (#{current_url})" unless safe_url?(current_url)

      uri = URI.parse(current_url)
      html_content = +""
      bytes_received = 0
      detected_captcha = false
      response_from_fragment = nil
      buffering_stopped = false
      last_match_check_bytes = 0

      response = HTTParty.get(
        uri,
        headers: headers,
        timeout: 8,
        stream_body: true,
        follow_redirects: false
      ) do |chunk|
        next if buffering_stopped

        # HTTParty 0.17+ yields a String-delegating ResponseFragment exposing
        # its Net::HTTPResponse. Capture that metadata before `break`, because
        # a non-local break exits HTTParty.get and makes its return value nil.
        # Older HTTParty versions may yield a String; in that case we stop
        # buffering but let the request finish normally.
        chunk_text = chunk.to_s
        remaining_bytes = MAX_BYTES - bytes_received
        html_content << chunk_text.byteslice(0, remaining_bytes) if remaining_bytes.positive?
        bytes_received += chunk_text.bytesize

        captcha_prefix = html_content.byteslice(0, CAPTCHA_PREFIX_BYTES).to_s
        if captcha_prefix.match?(Results::PageFetcher::CAPTCHA_REGEX)
          detected_captcha = true
          response_from_fragment = fragment_http_response(chunk)
          break if response_from_fragment

          buffering_stopped = true
          next
        end

        match_check_due = html_content.bytesize - last_match_check_bytes >= EARLY_MATCH_CHECK_INTERVAL
        matched_all_groups = if match_check_due
                               last_match_check_bytes = html_content.bytesize
                               early_exit_possible?(extract_text_safely(html_content))
                             else
                               false
                             end
        should_stop = matched_all_groups || bytes_received >= MAX_BYTES
        next unless should_stop

        response_from_fragment = fragment_http_response(chunk)
        break if response_from_fragment

        buffering_stopped = true
      end
      response ||= response_from_fragment

      if redirect_response?(response)
        redirect_url = URI.join(uri, response_header(response, "location")).to_s
        return stream_page_content(redirect_url, redirects_remaining - 1)
      end

      [html_content, detected_captcha || captcha_response?(response)]
    end

    def safe_url?(url_string)
      uri = URI.parse(url_string)
      return false unless %w[http https].include?(uri.scheme)
      return false if uri.host.blank? || uri.userinfo.present?

      addresses = Resolv.getaddresses(uri.host)
      return false if addresses.empty?

      addresses.none? { |address| private_or_restricted_ip?(IPAddr.new(address)) }
    rescue StandardError
      false
    end

    def private_or_restricted_ip?(ip)
      ip.loopback? || ip.private? || ip.link_local? || ip == IPAddr.new("169.254.169.254")
    end

    def fragment_http_response(chunk)
      chunk.http_response if chunk.respond_to?(:http_response)
    end

    def response_header(response, name)
      return unless response

      if response.respond_to?(:headers)
        response.headers[name]
      else
        response[name]
      end
    end

    def redirect_response?(response)
      response && response.code.to_i.in?([301, 302, 303, 307, 308]) && response_header(response, "location").present?
    end

    def captcha_response?(response)
      return false unless response

      status = response.code.to_i
      return true if [403, 429, 503].include?(status)

      response_header(response, "server").to_s.downcase.include?("cloudflare") && status != 200
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
