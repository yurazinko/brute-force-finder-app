# frozen_string_literal: true

module ResultFilterable
  extend ActiveSupport::Concern

  private

  def parse_filter_options(search_instance: nil)
    {
      status: params[:status],
      time_frame: params[:d],
      keyword: params[:q],
      sort: params[:sort].presence || Results::Query::DEFAULT_SORT,
      show_acknowledged: params[:show_acknowledged].presence || search_instance&.show_acknowledged,
      show_less_relevant: params[:show_less_relevant]
    }.compact
  end

  def fetch_filtered_results(base_scope, filter_options)
    @counts = Results::Counters.calculate_filtered(base_scope, filter_options, @search)
    @pagy, @results = pagy(
      Results::Query.call(base_scope, filter_options, search: @search)
    )
  end
end
