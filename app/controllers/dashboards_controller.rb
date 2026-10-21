# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    # Use one cutoff for both tables so their reporting periods match.
    @period_start = 30.days.ago

    @productive_domains = Result.top_domains_efficiency(since: @period_start, limit: 15)
    @loser_targets = Targets::LowYieldQuery.call(since: @period_start, limit: 10)
  end
end
