# frozen_string_literal: true

class TargetsController < ApplicationController
  before_action :set_target, only: %i[edit update destroy]
  before_action :load_form_options, only: %i[new edit]

  def new
    category = current_user.categories.find_by(id: params[:category_id])
    @target = Target.new(
      category: category,
      is_active: true,
      allow_query_strings: false
    )
  end

  def edit; end

  def create
    attributes = target_params
    @category = current_user.categories.find(attributes[:category_id])
    @target = @category.targets.build

    if @target.persist_record(attributes)
      respond_to_successful_create
    else
      respond_to_failed_create
    end
  end

  def update
    attributes = target_params

    if @target.persist_record(attributes)
      respond_to_successful_update
    else
      respond_to_failed_update
    end
  end

  def destroy
    category = @target.category
    @target.destroy
    redirect_to category_path(category), notice: "Target was removed."
  end

  private

  def set_target
    @target = current_user.targets.find(params.expect(:id))
  end

  def load_form_options
    @categories = current_user.categories.order(:name)
    @searches = current_user.searches.order(:title)
  end

  def target_params
    params.expect(target: [
                    :name, :domain, :is_active, :category_id, :allow_query_strings, { search_ids: [] }
                  ])
  end

  def respond_to_successful_create
    respond_to do |format|
      format.html { redirect_to category_path(@target.category), notice: "Target #{@target.name} added!" }
      format.json { render json: { target: target_payload(@target) }, status: :created }
    end
  end

  def respond_to_failed_create
    @category = @target.category
    respond_to do |format|
      format.html { redirect_to category_path(@category), alert: "Error: #{@target.errors.full_messages.join(', ')}" }
      format.json { render json: { errors: @target.errors.full_messages }, status: :unprocessable_content }
    end
  end

  def respond_to_successful_update
    respond_to do |format|
      format.html { redirect_to edit_target_path(@target.id), notice: "Target #{@target.name} updated" }
      format.json { head :no_content }
      format.js { head :no_content }
    end
  end

  def respond_to_failed_update
    respond_to do |format|
      format.html do
        load_form_options
        render :edit, status: :unprocessable_content
      end
      format.json { render json: { errors: @target.errors.full_messages }, status: :unprocessable_content }
      format.js { render json: @target.errors, status: :unprocessable_content }
    end
  end

  def target_payload(target)
    {
      id: target.id,
      name: target.name,
      domain: target.domain,
      category_id: target.category_id,
      is_active: target.is_active,
      allow_query_strings: target.allow_query_strings,
      edit_url: edit_target_path(target),
      category_url: category_path(target.category_id)
    }
  end
end
