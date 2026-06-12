# frozen_string_literal: true

class TargetsController < ApplicationController
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
    @target = Target.find(params.expect(:id))
    @target.update(target_params)
    head :no_content
  end

  def destroy
    @target = Target.find(params.expect(:id))
    category = @target.category
    @target.destroy
    redirect_to category_path(category), notice: "Target was removed."
  end

  private

  def target_params
    params.expect(target: %i[name domain is_active category_id])
  end
end
