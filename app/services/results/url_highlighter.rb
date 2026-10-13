# frozen_string_literal: true

module Results
  class UrlHighlighter
    include ActionView::Helpers::OutputSafetyHelper
    include ActionView::Helpers::TagHelper

    def self.call(...) = new(...).call

    def initialize(result, view_context)
      @result = result
      @view_context = view_context
    end

    def call
      url = @result.url
      return url if url.blank?

      uri = parse_uri(url)
      return escape_text(url) unless uri&.host

      process_valid_url(url, uri)
    rescue URI::InvalidURIError
      escape_text(url)
    end

    private

    def parse_uri(url)
      URI.parse(url)
    rescue StandardError
      nil
    end

    def escape_text(text)
      ERB::Util.html_escape(text)
    end

    def process_valid_url(url, uri)
      host = uri.host
      path = uri.path.presence || "/"
      query = uri.query.present? ? "?#{uri.query}" : ""

      target = find_target_for_result
      return format_url_parts_without_target(url, host, path, query) if target.blank? || target.domain.blank?

      target_domain = Results::UrlMatcher.clean_domain(target.domain)
      matched_pattern = find_active_matched_pattern(target, path)

      format_url_parts(
        full_url: url,
        host: host,
        path: path,
        query: query,
        target_domain: target_domain,
        pattern_str: matched_pattern&.path_pattern
      )
    end

    def find_target_for_result
      return @result.target if @result.respond_to?(:target) && @result.target.present?

      search = @result.search
      return nil unless search&.user

      user_targets = Target.joins(:category).where(categories: { user_id: search.user_id }).distinct
      user_targets.find { |target| Results::UrlMatcher.matches?(@result.url, target) }
    end

    def find_active_matched_pattern(target, path)
      target.target_patterns.active.sort_by { |p| -p.path_pattern.length }.find do |pattern|
        Results::UrlMatcher.match_pattern?(path, pattern.path_pattern)
      end
    end

    def format_url_parts_without_target(full_url, host, path, query)
      scheme_and_prefix = full_url.split(host).first || "https://"
      safe_join([escape_text(scheme_and_prefix), escape_text(host), escape_text(path), escape_text(query)])
    end

    def format_url_parts(options)
      scheme_and_prefix = options[:full_url].split(options[:host]).first || "https://"
      highlighted_host = build_highlighted_host(options[:host], options[:target_domain])
      highlighted_path = build_highlighted_path(options[:path], options[:pattern_str])

      safe_join([escape_text(scheme_and_prefix), highlighted_host, highlighted_path, escape_text(options[:query])])
    end

    def build_highlighted_host(host, target_domain)
      if host == target_domain || host.end_with?(".#{target_domain}")
        subdomain_part = host.delete_suffix(target_domain)
        safe_join([
                    escape_text(subdomain_part),
                    content_tag(:span, escape_text(target_domain), class: "text-breeze-text font-bold")
                  ])
      else
        escape_text(host)
      end
    end

    def build_highlighted_path(path, pattern_str)
      return escape_text(path) if pattern_str.blank? || pattern_str == "/"

      if pattern_str.include?("*") && Results::UrlMatcher.match_pattern?(path, pattern_str)
        return content_tag(:span, escape_text(path), class: "text-indigo-400 font-semibold")
      end

      if path.include?(pattern_str)
        parts = path.partition(pattern_str)
        return safe_join([
                           escape_text(parts[0]),
                           content_tag(:span, escape_text(parts[1]), class: "text-indigo-400 font-semibold"),
                           escape_text(parts[2])
                         ])
      end

      escape_text(path)
    end
  end
end
