# frozen_string_literal: true

Sidekiq::Cron.configure do |config|
  config.cron_schedule_file = "config/schedule.yml"

  config.cron_poll_interval = 30
end
