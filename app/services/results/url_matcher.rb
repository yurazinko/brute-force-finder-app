# frozen_string_literal: true

module Results
  class UrlMatcher
    def self.matches?(url, target)
      new(url, target).matches?
    end

    def self.matched_pattern(url, target)
      new(url, target).matched_pattern
    end

    def initialize(url, target)
      @url = url
      @target = target
      @www_prefix = Utils::UrlNormalizer::WWW_PREFIX
    end

    def matches?
      return true if @target.blank? || @target.domain.blank?

      target_domain = @target.domain.to_s.sub(%r{\Ahttps?://}, "").sub(@www_prefix, "").delete_suffix("/")

      uri = URI.parse(@url)
      result_host = uri.host&.sub(@www_prefix, "")

      return false unless host_matches?(result_host, target_domain)

      path_matches?(uri.path)
    rescue URI::InvalidURIError
      false
    end

    def matched_pattern
      return nil if @target.blank? || @target.domain.blank?

      target_domain = @target.domain.to_s.sub(%r{\Ahttps?://}, "").sub(@www_prefix, "").delete_suffix("/")

      uri = URI.parse(@url)
      result_host = uri.host&.sub(@www_prefix, "")

      return nil unless host_matches?(result_host, target_domain)

      find_matching_pattern(uri.path)
    rescue URI::InvalidURIError
      nil
    end

    private

    def host_matches?(result_host, target_host)
      return false if result_host.blank?

      result_host == target_host || result_host.end_with?(".#{target_host}")
    end

    def path_matches?(result_path)
      patterns = @target.target_patterns.active
      return true if patterns.empty? # Якщо патернів немає, дозволяємо прохід за хостом

      clean_result_path = result_path.to_s

      patterns.any? do |pattern|
        match_pattern?(clean_result_path, pattern.path_pattern)
      end
    end

    def find_matching_pattern(result_path)
      patterns = @target.target_patterns.active
      return nil if patterns.empty? # Якщо патернів немає, повертаємо nil (це нормально для таргетів без патернів)

      clean_result_path = result_path.to_s

      patterns.find do |pattern|
        match_pattern?(clean_result_path, pattern.path_pattern)
      end
    end

    def match_pattern?(path, pattern_str)
      # Дозволяємо зірочці (*) матчити будь-які символи, включаючи слеші (для вкладених шляхів на кшталт /blog/*/comments)
      regex_str = pattern_str.gsub("*", ".*")
      regexp = /\A#{regex_str}\z/
      path.match?(regexp)
    end
  end
end
