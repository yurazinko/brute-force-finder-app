# frozen_string_literal: true

class TargetPatternsController < ApplicationController
  before_action :load_result_context, only: %i[new create]
  before_action :set_target_pattern, only: %i[update destroy]

  def new
    @target_pattern = TargetPattern.new(path_pattern: @default_path)
  end

  def create
    target_id = params.dig(:target_pattern, :target_id) || @matched_target&.id
    path_pattern = params[:target_pattern][:path_pattern]

    if target_id.blank?
      uri = URI.parse(@result.url)
      domain = uri.host&.sub(Utils::UrlNormalizer::WWW_PREFIX, "")

      category_id = params.dig(:target_pattern, :category_id)
      category_name = params.dig(:target_pattern, :category_name)

      category = if category_id.present?
                   current_user.categories.find(category_id)
                 elsif category_name.present?
                   current_user.categories.find_or_create_by!(name: category_name.strip)
                 else
                   raise(ActiveRecord::RecordInvalid, Target.new.tap { |t| t.errors.add(:category, "can't be blank") })
                 end

      target = category.targets.find_or_create_by!(domain: domain) do |t|
        t.name = domain.split(".").first.capitalize
        t.is_active = true
      end

      target_id = target.id
    else
      target = Target.find(target_id)
    end

    Prompt.find_or_create_by!(search: @search, target: target) do |p|
      p.full_query_text = "site:#{target.domain} #{@search.query_conditions}"
      p.status = "pending"
    end

    if path_pattern.present? && path_pattern != "/"
      @target_pattern = TargetPattern.find_or_initialize_by(target_id: target_id, path_pattern: path_pattern)
      @target_pattern.is_active = true
      @target_pattern.save!
    end

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
  rescue ActiveRecord::RecordInvalid => e
    message = e.record.errors.full_messages.presence || ["Category is required"]
    redirect_back_or_to(root_path, alert: "Error: #{message.join(', ')}", status: :see_other)
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

    @result = Result.find(result_id)
    uri = URI.parse(@result.url)
    @default_path = uri.path.presence || "/"

    clean_path = @default_path.sub(%r{\A/+}, "").chomp("/")
    @path_segments = clean_path.split("/")

    @search = @result.search
    @available_targets = Target.joins(:category).where(categories: { user_id: current_user.id }).distinct

    @matched_target = @available_targets.find { |t| Results::UrlMatcher.matches?(@result.url, t) }
  rescue ActiveRecord::RecordNotFound
    redirect_back_or_to(root_path, alert: "Result not found.", status: :see_other)
  end

  def set_target_pattern
    @target_pattern = TargetPattern.find(params.expect(:id))
  end

  def target_pattern_params
    params.expect(target_pattern: %i[path_pattern is_active target_id])
  end
end
