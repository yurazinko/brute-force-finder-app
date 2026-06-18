# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    prepare_efficiency_metrics
    prepare_target_metrics

    @prompt_failures = Prompt.where.not(error_message: nil)
                             .group(:error_message).order(count_all: :desc).limit(5).count
  end

  private

  def prepare_efficiency_metrics
    @target_efficiency = Result.top_domains_efficiency
    @efficiency_max = @target_efficiency.values.max.to_i.nonzero? || 1
  end

  def prepare_target_metrics
    @loser_targets = Target.top_by_prompts_count(5)
    @target_prompts = Target.prompts_distribution_map
    @prompts_max = @target_prompts.values.max.to_i.nonzero? || 1
  end
end