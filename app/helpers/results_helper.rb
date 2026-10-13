# frozen_string_literal: true

module ResultsHelper
  def highlight_target_domain(result)
    url = result.url
    return url if url.blank?

    uri = begin
      URI.parse(url)
    rescue StandardError
      nil
    end
    return h(url) unless uri&.host

    host = uri.host
    path = uri.path.presence || "/"
    query = uri.query.present? ? "?#{uri.query}" : ""

    target = find_target_for_result(result)

    # Якщо таргета немає — не підсвічуємо хост взагалі, повертаємо початковий рядок
    return format_url_parts_without_target(url, host, path, query) if target.blank? || target.domain.blank?

    target_domain = target.domain.to_s.sub(%r{\Ahttps?://}, "").sub(Utils::UrlNormalizer::WWW_PREFIX,
                                                                    "").delete_suffix("/")
    matched_pattern = find_active_matched_pattern(target, path)

    format_url_parts(url, host, path, query, target_domain, matched_pattern&.path_pattern)
  rescue URI::InvalidURIError
    h(url)
  end

  private

  def find_target_for_result(result)
    return result.target if result.respond_to?(:target) && result.target.present?

    search = result.search
    return nil unless search&.user

    user_targets = Target.joins(:category).where(categories: { user_id: search.user_id }).distinct
    user_targets.find { |target| Results::UrlMatcher.matches?(result.url, target) }
  end

  def find_active_matched_pattern(target, path)
    target.target_patterns.active.sort_by { |p| -p.path_pattern.length }.find do |pattern|
      match_pattern_path?(path, pattern.path_pattern)
    end
  end

  def match_pattern_path?(path, pattern_str)
    # Зірочка матчить будь-які сегменти, включаючи слеші
    regex_str = pattern_str.gsub("*", ".*")
    path.match?(/\A#{regex_str}\z/)
  end

  def format_url_parts_without_target(full_url, host, path, query)
    scheme_and_prefix = full_url.split(host).first || "https://"
    safe_join(
      [
        h(scheme_and_prefix),
        h(host),
        h(path),
        h(query)
      ]
    )
  end

  def format_url_parts(full_url, host, path, query, target_domain, pattern_str)
    scheme_and_prefix = full_url.split(host).first || "https://"
    highlighted_host = build_highlighted_host(host, target_domain)
    highlighted_path = build_highlighted_path(path, pattern_str)

    safe_join(
      [
        h(scheme_and_prefix),
        highlighted_host,
        highlighted_path,
        h(query)
      ]
    )
  end

  # Підсвічуємо лише ту частину хосту, яка збігається з таргетом (наприклад, у pl.indeed.com підсвітиться лише indeed.com)
  def build_highlighted_host(host, target_domain)
    if host == target_domain || host.end_with?(".#{target_domain}")
      subdomain_part = host.delete_suffix(target_domain) # наприклад, "pl."
      safe_join([
                  h(subdomain_part),
                  content_tag(:span, h(target_domain), class: "text-breeze-text font-bold")
                ])
    else
      h(host)
    end
  end

  def build_highlighted_path(path, pattern_str)
    return h(path) if pattern_str.blank? || pattern_str == "/"

    if pattern_str.include?("*")
      escaped_pattern = Regexp.escape(pattern_str).gsub('\*', ".*")
      regex = /\A#{escaped_pattern}\z/

      return content_tag(:span, h(path), class: "text-indigo-400 font-semibold") if path.match?(regex)
    end

    if path.include?(pattern_str)
      parts = path.partition(pattern_str)
      return safe_join([
                         h(parts[0]),
                         content_tag(:span, h(parts[1]), class: "text-indigo-400 font-semibold"),
                         h(parts[2])
                       ])
    end

    h(path)
  end
end
