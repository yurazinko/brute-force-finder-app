# frozen_string_literal: true

class TargetsController < ApplicationController
  before_action :set_target, only: %i[edit update destroy]

  def edit; end

  def create
    @category = Category.find(target_params[:category_id])
    @target = @category.targets.build(target_params)

    if @target.save
      redirect_to category_path(@category), notice: "Target #{@target.name} added!"
    else
      redirect_to category_path(@category), alert: "Error: #{@target.errors.full_messages.join(', ')}"
    end
  end

  def update
    if @target.update(target_params)
      respond_to do |format|
        format.html { redirect_to category_path(@target.category_id) }
        format.json { head :no_content }
        format.js   { head :no_content }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @target.errors, status: :unprocessable_content }
      end
    end
  end

  def destroy
    category = @target.category
    @target.destroy
    redirect_to category_path(category), notice: "Target was removed."
  end

  private

  def set_target
    @target = Target.find(params.expect(:id))
  end

  def target_params
    params.expect(target: %i[name domain is_active category_id allow_query_strings])
  end
end
