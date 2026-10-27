# frozen_string_literal: true

module Alerts
  class DeadTargetsChecker
    def initialize(user)
      @user = user
    end

    def show_alert?
      return false if @user.blank?
      return false if dismissed?

      dead_targets_present?
    end

    private

    def dismissed?
      Rails.cache.exist?("user:#{@user.id}:dismissed_dead_targets")
    rescue StandardError
      false
    end

    def dead_targets_present?
      Rails.cache.fetch("user:#{@user.id}:has_dead_targets", expires_in: 1.hour) do
        category_ids = @user.category_ids
        next false if category_ids.empty?

        Targets::LowYieldQuery.call(since: 30.days.ago, limit: 1, category_ids: category_ids).any?
      end
    end
  end
end
