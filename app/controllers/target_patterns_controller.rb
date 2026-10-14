# frozen_string_literal: true

class TargetPatternsController < ApplicationController
  include TargetPatternsContext
  include TargetPatternsResponder

  before_action :set_target_pattern, only: %i[update destroy]

  def new
    @target_pattern = TargetPattern.new(path_pattern: @default_path)
  end

  def create
    target = resolve_target_configuration
    @target_pattern = find_or_build_created_pattern(target)
    respond_to_create(target)
  rescue ActiveRecord::RecordInvalid => e
    handle_validation_error(e)
  end

  def update
    success = @target_pattern.update(target_pattern_params)
    respond_to_update(success)
  end

  def destroy
    target = @target_pattern.target
    @target_pattern.destroy
    respond_to_destroy(target)
  end

  private

  def set_target_pattern
    @target_pattern = TargetPattern.find(params.expect(:id))
  end

  def target_pattern_params
    params.expect(target_pattern: %i[path_pattern is_active target_id category_id category_name allow_query_strings])
  end
end
