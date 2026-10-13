# frozen_string_literal: true

class TargetPatternsController < ApplicationController
  before_action :load_result_context, only: %i[new create], if: -> { params[:result_id].present? }
  before_action :set_target_pattern, only: %i[update destroy]

  def new
    @target_pattern = TargetPattern.new(path_pattern: @default_path)
  end

  def create
    target = resolve_target_configuration
    handle_post_creation(target)
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
    return unless params[:result_id]

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
        current_user: current_user,
        search: @search,
        result: @result,
        matched_target: @matched_target,
        pattern_params: target_pattern_params
      )
    else
      Targets::PatternConfigurationService.call_direct(pattern_params: target_pattern_params)
    end
  end

  def handle_post_creation(target)
    if @search.present?
      path_pattern = target_pattern_params[:path_pattern]
      @target_pattern = TargetPattern.find_or_create_by(target_id: target.id, path_pattern: path_pattern)
      handle_successful_creation
    else
      redirect_to edit_target_path(target), notice: "Path pattern added successfully.", status: :see_other
    end
  end

  def handle_successful_creation
    respond_to do |format|
      format.html do
        redirect_to search_path(@search), notice: "Target and pattern successfully configured!", status: :see_other
      end
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("modal_form_container", partial: "target_patterns/form_success_state",
                                                       locals: { search: @search, target_pattern: @target_pattern }),
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
    params.expect(target_pattern: %i[path_pattern is_active target_id category_id category_name allow_query_strings])
  end
end
