# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    prepare_efficiency_metrics
    prepare_target_metrics

    @prompt_failures = Prompt.joins(:search)
                             .where(searches: { user_id: current_user.id })
                             .where.not(error_message: nil)
                             .group(:error_message)
                             .order(count_all: :desc)
                             .limit(5)
                             .count
  end

  private

  def prepare_efficiency_metrics
    @target_efficiency = current_user.results.top_domains_efficiency
    @efficiency_max = @target_efficiency.values.max.to_i.nonzero? || 1
  end

  def prepare_target_metrics
    user_targets = current_user.targets
    @loser_targets = user_targets.top_by_prompts_count(5)
    @target_prompts = user_targets.prompts_distribution_map
    @prompts_max = @target_prompts.values.max.to_i.nonzero? || 1
  end
end
