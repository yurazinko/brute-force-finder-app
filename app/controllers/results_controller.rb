# frozen_string_literal: true

class ResultsController < ApplicationController
  def update
    @result = Result.find(params.expect(:id))

    @result.update!(result_params)

    @search = @result.search
    @counts = @search.calculate_counters

    respond_to do |format|
      format.turbo_stream { render :update, status: :ok }
      format.html { redirect_to search_path(@search, status: params[:current_tab], d: params[:d]) }
    end
  end

  private

  def result_params
    params.permit(:status, :acknowledged)
  end
end
