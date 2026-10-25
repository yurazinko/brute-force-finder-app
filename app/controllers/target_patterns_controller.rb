# frozen_string_literal: true

class TargetPatternsController < ApplicationController
  include TargetPatternsContext
  include TargetPatternsResponder

  before_action :set_target_pattern, only: %i[update destroy]

  def new
    @target_pattern = TargetPattern.new(path_pattern: @default_path)
  end

  def create
    explicit_target = target_pattern_params[:target_id].present?
    target = resolve_target_configuration
    @target_pattern = find_or_build_created_pattern(target)

    unless explicit_target
      @target_pattern.save! unless @target_pattern.persisted?
      attach_selected_searches(target) if @target_pattern.persisted?
    end

    respond_to_create(target)
  rescue ActiveRecord::RecordInvalid => e
    handle_validation_error(e)
  end

  def update
    success = @target_pattern.update(target_pattern_params.except(:search_ids))
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
    params.expect(target_pattern: [
                    :path_pattern, :is_active, :target_id, :category_id, :category_name, :allow_query_strings,
                    { search_ids: [] }
                  ])
  end

  def attach_selected_searches(target)
    search_ids = parsed_search_ids
    return if search_ids.empty?

    current_user.searches.where(id: search_ids).find_each do |search|
      find_or_create_prompt(target, search)
    end
  end

  def parsed_search_ids
    ids = Array(target_pattern_params[:search_ids]).filter_map do |id|
      Integer(id.to_s, 10)
    rescue StandardError
      nil
    end
    ids.uniq!
    ids
  end

  def find_or_create_prompt(target, search)
    query_text = "site:#{target.domain} #{search.query_conditions}".strip
    target.prompts.find_or_create_by!(search_id: search.id, full_query_text: query_text) do |prompt|
      prompt.status = "pending"
    end
  end
end
