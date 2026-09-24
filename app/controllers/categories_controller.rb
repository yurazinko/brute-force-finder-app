# frozen_string_literal: true

class CategoriesController < ApplicationController
  before_action :set_category, only: %i[show edit update destroy]

  def index
    @categories = current_user.categories.includes(:targets).order(:name)
  end

  def show; end

  def new
    @category = current_user.categories.new
  end

  def edit; end

  def create
    @category = current_user.categories.new(category_params)

    if @category.save
      redirect_to categories_path, notice: "Category successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @category.update(category_params)
      redirect_to categories_path, notice: "Category successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @category.destroy
    redirect_to categories_path, notice: "Category and all its linked targets were successfully deleted."
  end

  private

  def set_category
    @category = current_user.categories.includes(:targets).find(params.expect(:id))
  end

  def category_params
    params.expect(category: [:name])
  end
end
