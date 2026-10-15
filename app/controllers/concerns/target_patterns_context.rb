# frozen_string_literal: true

module TargetPatternsContext
  extend ActiveSupport::Concern

  included do
    before_action :load_result_context, only: %i[new create], if: -> { params[:result_id].present? }
  end

  private

  def load_result_context
    context = Targets::ResultContextService.call(current_user: current_user, result_id: params[:result_id])
    @result = context.result
    @default_path = context.default_path
    @path_segments = context.path_segments
    @search = context.search
    @available_targets = context.available_targets
    @matched_target = context.matched_target
  rescue ActiveRecord::RecordNotFound
    redirect_back_or_to(root_path, alert: "Result not found.", status: :see_other)
  end

  def resolve_target_configuration
    if params[:result_id].present?
      Targets::PatternConfigurationService.call(
        current_user: current_user, search: @search, result: @result,
        matched_target: @matched_target, pattern_params: target_pattern_params
      )
    else
      Targets::PatternConfigurationService.call_direct(pattern_params: target_pattern_params)
    end
  end

  def find_or_build_created_pattern(target)
    TargetPattern.find_by(
      target_id: target.id, path_pattern: target_pattern_params[:path_pattern]
    ) || target.target_patterns.order(:created_at).last
  end
end
