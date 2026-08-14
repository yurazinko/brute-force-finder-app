# frozen_string_literal: true

class ApplicationJob
  include Sidekiq::Job
  include Rls::Sidekiq

  private

  def broadcast_turbo_render(stream_target, template, assigns = {})
    Turbo::StreamsChannel.broadcast_render_to(
      stream_target, :results,
      template: template,
      assigns: assigns
    )
  rescue StandardError => e
    Rails.logger.error("[#{self.class.name}] Turbo broadcast failed: #{e.message}")
  end

  def broadcast_turbo_replace(channel, target:, partial:, locals: {})
    Turbo::StreamsChannel.broadcast_replace_to(
      channel,
      target: target,
      partial: partial,
      locals: locals
    )
  rescue StandardError => e
    Rails.logger.error("[#{self.class.name}] Turbo replace failed: #{e.message}")
  end
end
