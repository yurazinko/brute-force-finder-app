# frozen_string_literal: true

module Results
  class UrlMatcher
    def self.matches?(url, target)
      new(url, target).matches?
    end

    def self.domain_matches?(url, target)
      new(url, target).domain_matches?
    end

    def self.matched_pattern(url, target)
      new(url, target).matched_pattern
    end

    def self.match_pattern?(path, pattern_str)
      return false if path.blank? || pattern_str.blank?

      regex_str = pattern_str.gsub("*", ".*")
      path.match?(/\A#{regex_str}\z/)
    end

    def initialize(url, target)
      @url = url
      @target = target
      @www_prefix = Utils::UrlNormalizer::WWW_PREFIX
    end

    def domain_matches?
      return false if @target.blank? || @target.domain.blank?

      target_domain = self.class.clean_domain(@target.domain, @www_prefix)

      uri = URI.parse(@url)
      result_host = uri.host&.sub(@www_prefix, "")

      host_matches?(result_host, target_domain)
    rescue URI::InvalidURIError
      false
    end

    def matches?
      return false unless domain_matches?

      return true if active_sorted_patterns.empty?

      uri = URI.parse(@url)
      path_matches?(uri.path)
    rescue URI::InvalidURIError
      false
    end

    def matched_pattern
      return nil unless domain_matches?

      uri = URI.parse(@url)
      find_matching_pattern(uri.path)
    rescue URI::InvalidURIError
      nil
    end

    def active_patterns?
      active_sorted_patterns.any?
    end

    def self.clean_domain(domain, www_prefix = Utils::UrlNormalizer::WWW_PREFIX)
      domain.to_s.sub(%r{\Ahttps?://}, "").sub(www_prefix, "").delete_suffix("/")
    end

    private

    def host_matches?(result_host, target_host)
      return false if result_host.blank?

      result_host == target_host || result_host.end_with?(".#{target_host}")
    end

    def path_matches?(result_path)
      return true if active_sorted_patterns.empty?

      clean_result_path = result_path.to_s
      active_sorted_patterns.any? { |pattern| self.class.match_pattern?(clean_result_path, pattern.path_pattern) }
    end

    def find_matching_pattern(result_path)
      return nil if active_sorted_patterns.empty?

      clean_result_path = result_path.to_s
      active_sorted_patterns.find { |pattern| self.class.match_pattern?(clean_result_path, pattern.path_pattern) }
    end

    def active_sorted_patterns
      return [] if @target.blank?

      @active_sorted_patterns ||= @target.target_patterns.select(&:is_active).sort_by { |p| -p.path_pattern.length }
    end
  end
end
