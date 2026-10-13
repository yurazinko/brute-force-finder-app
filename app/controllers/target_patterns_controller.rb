# frozen_string_literal: true

class TargetPatternsController < ApplicationController
  before_action :load_result_context, only: %i[new create]
  before_action :set_target_pattern, only: %i[update destroy]

  def new
    @target_pattern = TargetPattern.new(path_pattern: @default_path)
  end

  def create
    Targets::PatternConfigurationService.call(
      current_user: current_user,
      search: @search,
      result: @result,
      matched_target: @matched_target,
      pattern_params: target_pattern_params
    )

    handle_successful_creation
  rescue ActiveRecord::RecordInvalid => e
    handle_validation_error(e)
  end

  def update
    if @target_pattern.update(target_pattern_params)
      redirect_back_or_to(edit_target_path(@target_pattern.target), notice: "Pattern updated successfully.",
                                                                    status: :see_other)
    else
      redirect_back_or_to(edit_target_path(@target_pattern.target), alert: "Failed to update pattern.",
                                                                    status: :see_other)
    end
  end

  def destroy
    target = @target_pattern.target
    @target_pattern.destroy
    redirect_back_or_to(edit_target_path(target), notice: "Pattern removed.", status: :see_other)
  end

  private

  def load_result_context
    result_id = params[:result_id] || params.dig(:target_pattern, :result_id)
    return unless result_id

    context = Targets::ResultContextService.call(current_user: current_user, result_id: result_id)
    @result = context.result
    @default_path = context.default_path
    @path_segments = context.path_segments
    @search = context.search
    @available_targets = context.available_targets
    @matched_target = context.matched_target
  rescue ActiveRecord::RecordNotFound
    redirect_back_or_to(root_path, alert: "Result not found.", status: :see_other)
  end

  def handle_successful_creation
    respond_to do |format|
      format.html do
        redirect_to search_path(@search), notice: "Target and pattern successfully configured!", status: :see_other
      end
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update("modal", ""),
          turbo_stream.action(:visit, search_path(@search))
        ]
      end
    end
  end

  def handle_validation_error(exception)
    message = exception.record.errors.full_messages.presence || ["Category is required"]
    redirect_back_or_to(root_path, alert: "Error: #{message.join(', ')}", status: :see_other)
  end

  def set_target_pattern
    @target_pattern = TargetPattern.find(params.expect(:id))
  end

  def target_pattern_params
    params.expect(target_pattern: %i[path_pattern is_active target_id category_id category_name])
  end
end
