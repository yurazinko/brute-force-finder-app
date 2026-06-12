# frozen_string_literal: true

module Utils
  module UrlNormalizer
    def self.normalize(url)
      return nil if url.blank?

      uri = URI.parse(url.strip)
      uri.query = nil
      uri.fragment = nil
      uri.to_s.downcase
    rescue URI::InvalidURIError
      url.strip.downcase
    end

    def self.hash(normalized_url)
      return nil if normalized_url.blank?

      Digest::SHA256.hexdigest(normalized_url)
    end
  end
end
