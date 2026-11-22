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

    StreamState = Struct.new(
      :html_content,
      :bytes_received,
      :detected_captcha,
      :response_from_fragment,
      :buffering_stopped,
      :last_match_check_bytes,
      keyword_init: true
    )

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
      state = initial_stream_state
      response = perform_stream_request(uri, state) || state.response_from_fragment

      return follow_redirect(uri, response, redirects_remaining) if redirect_response?(response)

      [state.html_content, state.detected_captcha || captcha_response?(response)]
    end

    def initial_stream_state
      StreamState.new(
        html_content: +"",
        bytes_received: 0,
        detected_captcha: false,
        response_from_fragment: nil,
        buffering_stopped: false,
        last_match_check_bytes: 0
      )
    end

    def perform_stream_request(uri, state)
      HTTParty.get(
        uri,
        headers: headers,
        timeout: 8,
        stream_body: true,
        follow_redirects: false
      ) do |chunk|
        next if state.buffering_stopped

        # HTTParty 0.17+ yields a String-delegating ResponseFragment exposing
        # its Net::HTTPResponse. Capture that metadata before `break`, because
        # a non-local break exits HTTParty.get and makes its return value nil.
        # Older HTTParty versions may yield a String; in that case we stop
        # buffering but let the request finish normally.
        break if process_chunk(chunk, state) == :break
      end
    end

    def process_chunk(chunk, state)
      append_chunk(chunk.to_s, state)

      if captcha_prefix_detected?(state.html_content)
        state.detected_captcha = true
        return stop_or_pause(chunk, state)
      end

      return unless should_stop_streaming?(state)

      stop_or_pause(chunk, state)
    end

    def append_chunk(chunk_text, state)
      remaining_bytes = MAX_BYTES - state.bytes_received
      state.html_content << chunk_text.byteslice(0, remaining_bytes) if remaining_bytes.positive?
      state.bytes_received += chunk_text.bytesize
    end

    def captcha_prefix_detected?(html_content)
      captcha_prefix = html_content.byteslice(0, CAPTCHA_PREFIX_BYTES).to_s
      captcha_prefix.match?(Results::PageFetcher::CAPTCHA_REGEX)
    end

    def should_stop_streaming?(state)
      matched_all_groups?(state) || state.bytes_received >= MAX_BYTES
    end

    def matched_all_groups?(state)
      return false if state.html_content.bytesize - state.last_match_check_bytes < EARLY_MATCH_CHECK_INTERVAL

      state.last_match_check_bytes = state.html_content.bytesize
      early_exit_possible?(extract_text_safely(state.html_content))
    end

    def stop_or_pause(chunk, state)
      state.response_from_fragment = fragment_http_response(chunk)
      return :break if state.response_from_fragment

      state.buffering_stopped = true
      nil
    end

    def follow_redirect(uri, response, redirects_remaining)
      redirect_url = URI.join(uri, response_header(response, "location")).to_s
      stream_page_content(redirect_url, redirects_remaining - 1)
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
