# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    @period = params[:period].present? ? params[:period].to_i : 30
    @period_start = @period.positive? ? @period.days.ago : 10.years.ago

    @productive_domains = Result.top_domains_efficiency(since: @period_start, limit: 15)
    @loser_targets = Targets::LowYieldQuery.call(since: @period_start, limit: 10)
  end
end
