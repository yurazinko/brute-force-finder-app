# frozen_string_literal: true

require "nokogiri"
require "time"

module Results
  class DateExtractor
    META_PROPERTIES = %w[
      article:published_time
      article:modified_time
      og:updated_time
      publication_date
      sailthru.date
    ].freeze

    META_NAMES = %w[
      date
      pubdate
      publishdate
      dc.date
      dc.date.issued
    ].freeze

    def self.extract(html_text, headers = {})
      new(html_text, headers).extract
    end

    def initialize(html_text, headers)
      @doc = html_text.present? ? Nokogiri::HTML(html_text) : nil
      @headers = headers || {}
    end

    def extract
      extract_from_meta || extract_from_json_ld || extract_from_headers
    end

    private

    def extract_from_meta
      return nil unless @doc

      META_PROPERTIES.each do |prop|
        node = @doc.at_css("meta[property='#{prop}']")
        time = parse_time(node&.[]("content"))
        return time if time
      end

      META_NAMES.each do |name|
        node = @doc.at_css("meta[name='#{name}']")
        time = parse_time(node&.[]("content"))
        return time if time
      end

      nil
    end

    def extract_from_json_ld
      return nil unless @doc

      @doc.css('script[type="application/ld+json"]').each do |script|
        data = begin
          JSON.parse(script.content)
        rescue StandardError
          nil
        end
        next unless data

        nodes = data.is_a?(Array) ? data : [data]
        nodes.each do |node|
          date_str = node["datePublished"] || node["dateModified"] || node["dateCreated"]
          time = parse_time(date_str)
          return time if time
        end
      end

      nil
    end

    def extract_from_headers
      last_modified = @headers["last-modified"] || @headers["Last-Modified"]
      parse_time(last_modified)
    end

    def parse_time(val)
      return nil if val.blank?

      Time.parse(val.to_s)
    rescue ArgumentError
      nil
    end
  end
end
