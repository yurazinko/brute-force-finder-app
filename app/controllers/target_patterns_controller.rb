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
    success = @target_pattern.update(target_pattern_params)
    flash_key = success ? :notice : :alert
    message = success ? "Pattern updated successfully." : "Failed to update pattern."

    if params[:result_id].present?
      redirect_to new_target_pattern_path(result_id: params[:result_id], redirect_to: params[:redirect_to]),
                  flash_key => message, status: :see_other
    else
      redirect_back_or_to edit_target_path(@target_pattern.target),
                          flash_key => message, status: :see_other
    end
  end

  def destroy
    target = @target_pattern.target
    @target_pattern.destroy

    if params[:result_id].present?
      redirect_to new_target_pattern_path(result_id: params[:result_id], redirect_to: params[:redirect_to]),
                  notice: "Pattern removed.", status: :see_other
    else
      redirect_back_or_to(edit_target_path(target), notice: "Pattern removed.", status: :see_other)
    end
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
    redirect_url = params[:redirect_to].presence || (
      @search.present? ? search_path(@search) : edit_target_path(target)
    )

    if @search.present? && params[:result_id].present?
      path_pattern = target_pattern_params[:path_pattern]
      @target_pattern = TargetPattern.find_or_create_by(target_id: target.id, path_pattern: path_pattern)
      handle_successful_creation(redirect_url)
    else
      redirect_to redirect_url, notice: "Path pattern added successfully.", status: :see_other
    end
  end

  def handle_successful_creation(redirect_url)
    respond_to do |format|
      format.html do
        redirect_to redirect_url, notice: "Target and pattern successfully configured!", status: :see_other
      end

      format.turbo_stream do
        partial_locals = { search: @search, target_pattern: @target_pattern, redirect_url: redirect_url }
        render turbo_stream: [
          turbo_stream.replace(
            "modal_form_container", partial: "target_patterns/form_success_state", locals: partial_locals
          ),
          turbo_stream.action(:visit, redirect_url)
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
