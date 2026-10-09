# frozen_string_literal: true

module Utils
  class UrlNormalizer
    WWW_PREFIX = "www."

    def self.normalize(url, target_configs: {})
      return nil if url.blank?

      uri = URI.parse(url.strip)
      domain = extract_domain(uri.host)
      return nil if domain.blank?

      keep_query = should_keep_query?(domain, target_configs)

      if keep_query && uri.query.present?
        "#{uri.scheme}://#{uri.host}#{uri.path}?#{uri.query}"
      else
        "#{uri.scheme}://#{uri.host}#{uri.path}"
      end
    rescue URI::InvalidURIError
      nil
    end

    def self.extract_domain(host)
      return nil if host.blank?

      host.start_with?(WWW_PREFIX) ? host.sub(WWW_PREFIX, "") : host
    end

    def self.clean_domain_string(domain_str)
      host = domain_str.to_s.sub(%r{\Ahttps?://}, "").split("/").first
      extract_domain(host)
    end

    def self.hash(url)
      Digest::SHA256.hexdigest(url.downcase)
    end

    private_class_method def self.should_keep_query?(domain, target_configs)
      target_configs.any? do |target_domain, allow_query|
        (domain == target_domain || domain.end_with?(".#{target_domain}")) && allow_query
      end
    end
  end
end
