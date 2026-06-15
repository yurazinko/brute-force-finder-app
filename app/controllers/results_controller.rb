class ResultsController < ApplicationController
  def update
    @result = Result.find(params.expect(:id))

    return unless @result.update(status: params[:status])

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("result_#{@result.id}")
      end

      format.html { redirect_to search_path(@result.search) }
    end
  end
end
