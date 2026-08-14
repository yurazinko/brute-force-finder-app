# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pagy::Method
  include Rls::Context

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!
  around_action :set_rls_user

  private

  def set_rls_user(&)
    with_rls_user(current_user&.id, &)
  end
end
