# frozen_string_literal: true

module TargetPatternsResponder
  extend ActiveSupport::Concern

  private

  def pattern_payload(pattern)
    { id: pattern.id, path_pattern: pattern.path_pattern, is_active: pattern.is_active? }
  end

  def respond_to_create(target)
    respond_to do |format|
      format.json { render json: { success: true, pattern: pattern_payload(@target_pattern) } }
      format.html { handle_post_creation(target) }
    end
  end

  def respond_to_update(success)
    message = success ? "Pattern updated successfully." : "Failed to update pattern."
    flash_key = success ? :notice : :alert

    respond_to do |format|
      format.json { render_update_response(success) }
      format.html { redirect_after_update(flash_key, message) }
    end
  end

  def render_update_response(success)
    if success
      render json: { success: true, pattern: pattern_payload(@target_pattern) }
    else
      render json: { success: false, errors: @target_pattern.errors.full_messages }, status: :unprocessable_content
    end
  end

  def redirect_after_update(flash_key, message)
    if params[:result_id].present?
      redirect_to new_target_pattern_path(result_id: params[:result_id], redirect_to: params[:redirect_to]),
                  flash_key => message, status: :see_other
    else
      redirect_back_or_to edit_target_path(@target_pattern.target), flash_key => message, status: :see_other
    end
  end

  def respond_to_destroy(target)
    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_after_destroy(target) }
    end
  end

  def redirect_after_destroy(target)
    if params[:result_id].present?
      redirect_to new_target_pattern_path(result_id: params[:result_id], redirect_to: params[:redirect_to]),
                  notice: "Pattern removed.", status: :see_other
    else
      redirect_back_or_to(edit_target_path(target), notice: "Pattern removed.", status: :see_other)
    end
  end

  def handle_post_creation(target)
    redirect_url = params[:redirect_to].presence || (@search.present? ? search_path(@search) : edit_target_path(target))

    if @search.present? && params[:result_id].present?
      @target_pattern =
        TargetPattern.find_or_create_by(target_id: target.id, path_pattern: target_pattern_params[:path_pattern])
      handle_successful_creation(redirect_url)
    else
      redirect_to redirect_url, notice: "Path pattern added successfully.", status: :see_other
    end
  end

  def handle_successful_creation(redirect_url)
    partial_locals = { search: @search, target_pattern: @target_pattern, redirect_url: redirect_url }
    respond_to do |format|
      format.html do
        redirect_to redirect_url,
                    notice: "Target and pattern successfully configured!", status: :see_other
      end
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("modal_form_container",
                               partial: "target_patterns/form_success_state", locals: partial_locals),
          turbo_stream.action(:visit, redirect_url)
        ]
      end
    end
  end

  def handle_validation_error(exception)
    message = exception.record.errors.full_messages.presence || ["Category is required"]
    respond_to do |format|
      format.json { render json: { errors: exception.record.errors.full_messages }, status: :unprocessable_content }
      format.html { redirect_back_or_to(root_path, alert: "Error: #{message.join(', ')}", status: :see_other) }
    end
  end
end
