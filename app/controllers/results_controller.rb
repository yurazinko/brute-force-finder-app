# frozen_string_literal: true

class ResultsController < ApplicationController
  include ResultFilterable

  before_action :find_result, only: [:update]

  def index
    @selected_search_ids = params[:search_ids] || []
    base_scope = scope_for_selected_searches

    filtered_results = filter_results(base_scope, show_acknowledged_fallback: false)
    @counts = calculate_counters_for(base_scope, show_acknowledged_fallback: false)

    @pagy, @results = pagy(filtered_results.order(sorting_order))
    @index_path_helper = :results_path
  end

  def update
    @result.update!(result_params)
    @search = @result.search

    @counts = calculate_counters

    respond_to do |format|
      format.turbo_stream { render :update, status: :ok }
      format.html { redirect_to search_path(@search, status: params[:current_tab], d: params[:d]) }
    end
  end

  private

  def find_result
    @result = Result.find(params.expect(:id))
  end

  def calculate_counters
    if params[:from_global_index] == "true"
      @selected_search_ids = params[:search_ids] || []
      calculate_counters_for(scope_for_selected_searches, show_acknowledged_fallback: false)
    else
      calculate_counters_for(@search.results, show_acknowledged_fallback: false)
    end
  end

  def result_params
    params.permit(:status, :acknowledged)
  end

  def scope_for_selected_searches
    scope = Result.all
    scope = scope.where(search_id: @selected_search_ids) if @selected_search_ids.any?
    scope
  end
end
