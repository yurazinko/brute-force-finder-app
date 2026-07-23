# frozen_string_literal: true

class ResultsController < ApplicationController
  include ResultFilterable

  before_action :set_scopes_and_options

  def index
    @selected_search_ids = params[:search_ids] || []

    fetch_filtered_results(@base_scope, @filter_options)

    respond_to do |format|
      format.html { render "searches/show" if params[:turbo_frame].present? }
      format.html
      format.turbo_stream
    end
  end

  def update
    @result = Result.find(params.expect(:id))

    if @result.update(result_params)
      prepare_update_variables
      respond_to_successful_update
    else
      head :unprocessable_content
    end
  end

  private

  def set_scopes_and_options
    @search = Search.find_by(id: params[:search_id])

    @base_scope = if @search
                    @search.results
                  elsif params[:search_ids].present?
                    Result.where(search_id: params[:search_ids])
                  else
                    Result.all
                  end

    @filter_options = parse_filter_options(search_instance: @search)
  end

  def prepare_update_variables
    dom_count = params[:current_dom_count].to_i
    dom_count = 20 if dom_count.zero?

    @next_card = Results::FeedRefill.next_card(
      base_scope: @base_scope,
      removed_id: @result.id,
      current_dom_count: dom_count,
      options: @filter_options
    )

    @counts = Results::Counters.calculate_filtered(@base_scope, @filter_options, @search)
  end

  def respond_to_successful_update
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_update_payload }
      format.html { redirect_after_update }
    end
  end

  def turbo_stream_update_payload
    streams = [
      turbo_stream.remove(@result),
      turbo_stream.replace(
        "search_tabs_navigation",
        partial: "searches/tabs_counters",
        locals: { search: @search, counts: @counts }
      )
    ]

    if @next_card
      streams << turbo_stream.append("results_pool_list", partial: "results/result_card",
                                                          locals: { result: @next_card })
    end

    streams
  end

  def redirect_after_update
    common_params = {
      status: params[:status],
      d: params[:d],
      q: params[:q],
      sort: params[:sort],
      show_acknowledged: params[:show_acknowledged]
    }

    if @search.present?
      redirect_to search_path(@search, common_params)
    else
      redirect_to results_path(common_params.merge(search_ids: params[:search_ids]))
    end
  end

  def result_params
    params.expect(result: %i[status acknowledged])
  end
end
