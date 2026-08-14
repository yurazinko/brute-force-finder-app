# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }
  let!(:category) { Category.create!(name: "Job Boards") }

  let(:valid_attributes) { { category: { name: "Aggregators" } } }
  let(:invalid_attributes) { { category: { name: "" } } }

  before do
    sign_in user if respond_to?(:sign_in)
  end

  describe "GET /categories (index)" do
    it "returns a successful response and renders the index template" do
      get categories_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Job Boards")
    end

    it "returns categories sorted alphabetically by name" do
      Category.create!(name: "Z Platforms")
      Category.create!(name: "A Boards")

      get categories_path

      expect(response.body.index("A Boards")).to be < response.body.index("Job Boards")
      expect(response.body.index("Job Boards")).to be < response.body.index("Z Platforms")
    end
  end

  describe "GET /categories/:id (show)" do
    context "when the category exists" do
      it "returns a successful response and includes the category name" do
        get category_path(category)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Job Boards")
      end
    end

    context "when the category does not exist" do
      it "fails gracefully and returns a 404 not found status" do
        get category_path(id: 999_999)
        expect(response).to have_http_status(:not_found)
      end
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

        expect(response).to have_http_status(:found)
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
        expect(response).to have_http_status(:found)
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
    context "when category has no linked targets" do
      it "destroys the requested category and redirects to index" do
        expect do
          delete category_path(category)
        end.to change(Category, :count).by(-1)

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(categories_path)

        follow_redirect!
        expect(response.body).to include("Category and all its linked targets were successfully deleted.")
      end
    end

    context "when category has linked targets (cascading destroy check)" do
      before do
        category.targets.create!(name: "Lever", domain: "lever.co", is_active: true)
        category.targets.create!(name: "Greenhouse", domain: "greenhouse.io", is_active: true)
      end

      it "destroys the category along with all its dependent targets" do
        expect do
          delete category_path(category)
        end.to change(Category, :count).by(-1)
                                       .and change(Target, :count).by(-2)

        expect(response).to redirect_to(categories_path)
      end
    end
  end
end
