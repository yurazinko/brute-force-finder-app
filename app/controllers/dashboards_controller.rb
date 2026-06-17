# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    @target_efficiency = Result.group("SUBSTRING(url FROM 'https?://([^/]+)')")
                               .order(count_all: :desc).limit(5).count
                               .transform_keys { |k| k.nil? ? "Unknown" : k.to_s }
    @efficiency_max = begin
      @target_efficiency.values.max.to_i
    rescue StandardError
      1
    end

    @loser_targets = Target.joins(:prompts)
                           .left_joins(:category)
                           .select("targets.name, targets.domain, COUNT(DISTINCT prompts.id) as prompts_count")
                           .group("targets.id, targets.name, targets.domain")
                           .order(prompts_count: :desc)
                           .limit(5)

    @target_prompts = Target.joins(:prompts).group("targets.name")
                            .order(count_all: :desc).limit(5).count
    @prompts_max = begin
      @target_prompts.values.max.to_i
    rescue StandardError
      1
    end

    @prompt_failures = Prompt.where.not(error_message: nil)
                             .group(:error_message).order(count_all: :desc).limit(5).count
  end
end
