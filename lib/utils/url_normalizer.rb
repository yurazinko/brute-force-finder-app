# frozen_string_literal: true

module Utils
  class UrlNormalizer
    WWW_PREFIX = "www."

    def self.normalize(url, target_configs: {})
      return nil if url.blank?

      uri = parse_uri(url)
      return nil if uri&.host.blank? || uri&.scheme.blank?

      domain = extract_domain(uri.host)
      return nil if domain.blank?

      build_normalized_string(uri, domain, target_configs)
    rescue URI::InvalidURIError
      nil
    end

    def self.extract_domain(host)
      return nil if host.blank?

      downcased_host = host.downcase
      downcased_host.start_with?(WWW_PREFIX) ? downcased_host.sub(WWW_PREFIX, "") : downcased_host
    end

    def self.clean_domain_string(domain_str)
      host = domain_str.to_s.sub(%r{\Ahttps?://}, "").split("/").first
      extract_domain(host)
    end

    def self.hash(url)
      normalized_url = normalize(url)
      return nil if normalized_url.blank?

      Digest::SHA256.hexdigest(normalized_url)
    end

    def self.parse_uri(url)
      URI.parse(url.strip)
    end

    def self.build_normalized_string(uri, domain, target_configs)
      scheme = uri.scheme.downcase
      path = uri.path.to_s
      query = should_keep_query?(domain, target_configs) ? uri.query : nil

      query.present? ? "#{scheme}://#{domain}#{path}?#{query}" : "#{scheme}://#{domain}#{path}"
    end

    def self.should_keep_query?(domain, target_configs)
      target_configs.any? do |target_domain, allow_query|
        downcased_target = target_domain.to_s.downcase
        (domain == downcased_target || domain.end_with?(".#{downcased_target}")) && allow_query
      end
    end
  end
end
