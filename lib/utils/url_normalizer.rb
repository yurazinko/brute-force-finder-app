# frozen_string_literal: true

module Utils
  class UrlNormalizer
    def self.normalize(url, keep_query: false)
      return nil if url.blank?

      uri = URI.parse(url.strip)

      if keep_query
        "#{uri.scheme}://#{uri.host}#{uri.path}?#{uri.query}".chomp("?")
      else
        "#{uri.scheme}://#{uri.host}#{uri.path}"
      end
    rescue URI::InvalidURIError
      nil
    end

    def self.hash(url)
      Digest::SHA256.hexdigest(url.downcase)
    end
  end
end
