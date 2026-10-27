# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    @period = params[:period].present? ? params[:period].to_i : 30
    @period_start = @period.positive? ? @period.days.ago : 10.years.ago

    @productive_domains = Result.top_domains_efficiency(since: @period_start, limit: 15)

    @loser_targets = Targets::LowYieldQuery.call(since: @period_start, category_ids: current_user.category_ids,
                                                 limit: 10)

    dismiss_alerts if @dead_targets_alert
  end

  private

  def dismiss_alerts
    cache_key = "user:#{current_user.id}:dismissed_dead_targets"
    Rails.cache.write(cache_key, true, expires_in: 7.days)
  end
end
