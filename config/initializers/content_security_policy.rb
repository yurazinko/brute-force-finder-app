# frozen_string_literal: true

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.object_src :none
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :https, :data
    policy.font_src :self, :https, :data
    policy.connect_src :self, :https, :wss
    policy.media_src :self, :https
  end

  # Importmap and Rails-generated script tags receive a nonce; avoid unsafe-eval.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
