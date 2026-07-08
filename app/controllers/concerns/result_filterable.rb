# frozen_string_literal: true

module ResultFilterable
  extend ActiveSupport::Concern

  included do
    before_action :set_filter_params
  end

  private

  def set_filter_params
    @current_status = params[:status]
    @search_query = params[:q]
    @time_frame = params[:d]
    @sort_param = params[:sort]
  end

  def filter_results(base_scope, show_acknowledged_fallback: false)
    scope = base_scope.by_time_frame(@time_frame)
    scope = apply_status_and_acknowledgement(scope, show_acknowledged_fallback)
    scope.search_by_keyword(@search_query)
  end

  def sorting_order
    {
      "created_asc" => { created_at: :asc },
      "updated_desc" => { updated_at: :desc },
      "updated_asc" => { updated_at: :asc }
    }.fetch(@sort_param, { created_at: :desc })
  end

  def calculate_counters_for(scope, show_acknowledged_fallback: false)
    return {} if params[:page].to_i > 1

    ack_filter = acknowledgement_filter(show_acknowledged_fallback)

    {
      "unread" => scope.where(status: "unread", acknowledged: ack_filter).count,
      "watched" => scope.where(status: "watched").count,
      "interesting" => scope.where(status: "interesting").count,
      "garbage" => scope.where(status: "garbage").count
    }.with_indifferent_access
  end

  def apply_status_and_acknowledgement(scope, fallback)
    if %w[garbage interesting watched].include?(@current_status)
      scope.by_status(@current_status)
    else
      scope.where(status: "unread", acknowledged: acknowledgement_filter(fallback))
    end
  end

  def acknowledgement_filter(fallback)
    show_ack_enabled?(fallback) ? [true, false] : false
  end

  def show_ack_enabled?(fallback)
    return ActiveModel::Type::Boolean.new.cast(params[:show_acknowledged]) if params[:show_acknowledged].present?

    return fallback if params[:from_global_index] == "true"

    if defined?(@search) && @search.present? && @search.respond_to?(:show_acknowledged?)
      return @search.show_acknowledged?
    end

    fallback
  end
end
