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
    @sort_param = params[:sort].presence || "relevance_desc"
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

  def acknowledgement_filter(fallback)
    show_ack_enabled?(fallback) ? [true, false] : false
  end

  def show_ack_enabled?(fallback)
    return ActiveModel::Type::Boolean.new.cast(params[:show_acknowledged]) if params[:show_acknowledged].present?

    if defined?(@search) && @search.present? && @search.respond_to?(:show_acknowledged?)
      return @search.show_acknowledged?
    end

    fallback
  end

  def parse_filter_options(search_instance: nil)
    {
      status: params[:status],
      time_frame: params[:d],
      keyword: params[:q],
      sort: params[:sort].presence || "relevance_desc",
      show_acknowledged: params[:show_acknowledged].presence || search_instance&.show_acknowledged
    }
  end

  def fetch_filtered_results(base_scope, filter_options)
    @counts = Results::Counters.calculate_filtered(base_scope, filter_options)

    @pagy, @results = pagy(Results::Index.new(base_scope, filter_options, @search).call)
  end
end
