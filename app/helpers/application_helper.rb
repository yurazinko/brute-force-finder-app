# frozen_string_literal: true

module ApplicationHelper
  include Pagy::Method

  def safe_redirect_path(path, fallback:)
    return fallback if path.blank?

    uri = URI.parse(path)
    path_only = uri.path
    return fallback unless path_only&.start_with?("/") && !path_only&.start_with?("//")

    Rails.application.routes.recognize_path(path_only)
    path
  rescue StandardError
    fallback
  end

  def safe_back_path(fallback: root_path)
    referer = request.referer
    return fallback if referer.blank?

    referer_uri = URI.parse(referer)

    if referer_uri.path == request.path
      fallback
    else
      referer
    end
  rescue URI::InvalidURIError
    fallback
  end
end
