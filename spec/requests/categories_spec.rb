# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories", type: :request do
  let!(:category) { Category.create!(name: "Job Boards") }

  let(:valid_attributes) { { category: { name: "Aggregators" } } }
  let(:invalid_attributes) { { category: { name: "" } } }

  describe "GET /categories (index)" do
    it "returns a successful response and renders the index template" do
      get categories_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Job Boards")
    end
  end

  describe "GET /categories/:id (show)" do
    it "returns a successful response" do
      get category_path(category)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Job Boards")
    end
  end

  describe "GET /categories/new (new)" do
    it "returns a successful response" do
      get new_category_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /categories/:id/edit (edit)" do
    it "returns a successful response" do
      get edit_category_path(category)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /categories (create)" do
    context "with valid parameters" do
      it "creates a new Category and redirects to index" do
        expect do
          post categories_path, params: valid_attributes
        end.to change(Category, :count).by(1)

        expect(response).to redirect_to(categories_path)

        follow_redirect!
        expect(response.body).to include("Category successfully created.")
      end
    end

    context "with invalid parameters" do
      it "does not create a new Category and returns unprocessable content" do
        expect do
          post categories_path, params: invalid_attributes
        end.not_to change(Category, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH/PUT /categories/:id (update)" do
    context "with valid parameters" do
      it "updates the requested category and redirects to index" do
        patch category_path(category), params: valid_attributes

        expect(category.reload.name).to eq("Aggregators")
        expect(response).to redirect_to(categories_path)

        follow_redirect!
        expect(response.body).to include("Category successfully updated.")
      end
    end

    context "with invalid parameters" do
      it "does not update the category and returns unprocessable content" do
        patch category_path(category), params: invalid_attributes

        expect(category.reload.name).to eq("Job Boards")
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /categories/:id (destroy)" do
    it "destroys the requested category and redirects to index" do
      expect do
        delete category_path(category)
      end.to change(Category, :count).by(-1)

      expect(response).to redirect_to(categories_path)

      follow_redirect!
      expect(response.body).to include("Category and all its linked targets were successfully deleted.")
    end
  end
end
