# frozen_string_literal: true

# app/services/results/url_matcher.rb
module Results
  class UrlMatcher
    def self.matches?(url, target)
      new(url, target).matches?
    end

    def initialize(url, target)
      @url = url
      @target = target
    end

    def matches?
      return true if @target.blank? || @target.domain.blank?

      target_str = @target.domain.to_s.sub(%r{\Ahttps?://}, "").sub(DataTransformer::WWW_PREFIX, "")
      target_host, target_path = target_str.delete_suffix("/").split("/", 2)

      uri = URI.parse(@url)
      result_host = uri.host&.sub(DataTransformer::WWW_PREFIX, "")

      return false unless host_matches?(result_host, target_host)

      path_matches?(uri.path, target_path)
    rescue URI::InvalidURIError
      false
    end

    private

    def host_matches?(result_host, target_host)
      return false if result_host.blank?

      result_host == target_host || result_host.end_with?(".#{target_host}")
    end

    def path_matches?(result_path, target_path)
      return true if target_path.blank?

      clean_result_path = result_path.to_s.delete_prefix("/")
      clean_target_path = target_path.delete_prefix("/")

      clean_result_path.start_with?(clean_target_path)
    end
  end
end
