# frozen_string_literal: true

require "httparty"

module Results
  class StreamingPageFetcher
    MAX_BYTES = 1_048_576
    CHUNK_SIZE = 16_384

    class AbortStream < StandardError; end

    class TextExtractor < Nokogiri::XML::SAX::Document
      attr_reader :extracted_text

      def initialize
        super
        @extracted_text = +""
        @inside_ignored_tag = false
        @ignored_depth = 0
      end

      def start_element(name, _attrs = [])
        case name.downcase
        when "script", "style", "noscript", "svg", "header", "footer", "nav"
          @ignored_depth += 1
          @inside_ignored_tag = true
        end
      end

      def end_element(name)
        case name.downcase
        when "script", "style", "noscript", "svg", "header", "footer", "nav"
          @ignored_depth -= 1
          @inside_ignored_tag = false if @ignored_depth <= 0
        end
      end

      def characters(string)
        return if @inside_ignored_tag

        @extracted_text << string
        @extracted_text << " "
      end
    end

    def self.fetch_and_match(url, keyword_groups: [])
      new(url, keyword_groups: keyword_groups).fetch
    end

    def initialize(url, keyword_groups: [])
      @url = url
      @keyword_groups = keyword_groups.map { |group| group.map(&:downcase) }
      @bytes_received = 0
    end

    def fetch
      handler = TextExtractor.new
      parser = Nokogiri::HTML::SAX::PushParser.new(handler)

      process_stream(parser, handler)
      parser.finish
      build_result(handler.extracted_text, status: :verified)
    rescue AbortStream => e
      handle_abort_stream(e, handler.extracted_text)
    rescue StandardError => e
      Rails.logger.warn("[StreamingPageFetcher] Failed to fetch #{@url}: #{e.message}")
      Results::PageFetcher::FetchResult.new(text: "", status: :error)
    end

    private

    def process_stream(parser, handler)
      HTTParty.get(@url, headers: headers, timeout: 8, stream_body: true) do |chunk|
        @bytes_received += chunk.bytesize
        parser << chunk

        validate_chunk!(chunk, handler.extracted_text)
      end
    end

    def validate_chunk!(chunk, current_text)
      raise AbortStream, :captcha if @bytes_received <= 32_768 && captcha_in_chunk?(chunk)
      raise AbortStream, :verified if early_exit_possible?(current_text)
      raise AbortStream, :limit_reached if @bytes_received >= MAX_BYTES
    end

    def handle_abort_stream(exception, extracted_text)
      if exception.message == :captcha
        Results::PageFetcher::FetchResult.new(text: "", status: :captcha)
      else
        build_result(extracted_text, status: :verified)
      end
    end

    def captcha_in_chunk?(chunk)
      chunk.match?(Results::PageFetcher::CAPTCHA_REGEX)
    end

    def early_exit_possible?(current_text)
      return false if @keyword_groups.empty?

      normalized_text = current_text.downcase

      @keyword_groups.all? do |group|
        group.any? { |kw| normalized_text.include?(kw) }
      end
    end

    def build_result(raw_text, status:)
      raw_text.gsub!(/\s+/, " ")
      raw_text.strip!
      raw_text.downcase!

      Results::PageFetcher::FetchResult.new(text: raw_text, status: status)
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
