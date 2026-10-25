# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Targets", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }
  let!(:category) { Category.create!(name: "Job Boards", user: user) }
  let!(:other_category) { Category.create!(name: "Social Media", user: user) }
  let!(:search) { Search.create!(title: "Ruby Developer", user: user, query_conditions: "ruby developer") }
  let!(:target) { Target.create!(category: category, name: "Indeed", domain: "indeed.com", is_active: true) }

  before do
    host! "localhost"
    ActionController::Base.allow_forgery_protection = false
    sign_in user if respond_to?(:sign_in)
  end

  describe "GET /targets/new" do
    it "renders the new template successfully" do
      get new_target_path(category_id: category.id)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /targets/:id/edit" do
    it "renders the edit template successfully" do
      get edit_target_path(target)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /targets (create)" do
    context "with valid parameters (HTML format)" do
      let(:valid_params) do
        {
          target: {
            name: "LinkedIn",
            domain: "linkedin.com",
            is_active: true,
            category_id: category.id,
            allow_query_strings: true,
            search_ids: [search.id.to_s]
          }
        }
      end

      it "creates a new Target, synchronizes searches, and redirects to the category show page" do
        expect do
          post targets_path, params: valid_params
        end.to change(Target, :count).by(1)

        expect(response).to redirect_to(category_path(category))

        follow_redirect!
        expect(response.body).to include("Target LinkedIn added!")

        created_target = Target.find_by(domain: "linkedin.com")
        expect(created_target.allow_query_strings).to be_truthy
      end
    end

    context "with valid parameters (JSON format)" do
      let(:json_params) do
        {
          target: {
            name: "GitHub Jobs",
            domain: "github.com",
            is_active: true,
            category_id: category.id
          }
        }
      end

      it "creates a new Target and returns created status with payload" do
        expect do
          post targets_path, params: json_params, as: :json
        end.to change(Target, :count).by(1)

        expect(response).to have_http_status(:created)
        json_response = response.parsed_body
        expect(json_response["target"]["name"]).to eq("GitHub Jobs")
      end
    end

    context "with invalid parameters (HTML format)" do
      let(:invalid_params) do
        {
          target: {
            name: "",
            domain: "invalid.com",
            category_id: category.id
          }
        }
      end

      it "does not create a target and redirects to category with alert errors" do
        expect do
          post targets_path, params: invalid_params
        end.not_to change(Target, :count)

        expect(response).to redirect_to(category_path(category))

        follow_redirect!
        expect(CGI.unescapeHTML(response.body)).to include("Error: Name can't be blank")
      end
    end

    context "with invalid parameters (JSON format)" do
      let(:invalid_json_params) do
        {
          target: {
            name: "",
            domain: "invalid.com",
            category_id: category.id
          }
        }
      end

      it "does not create a target and returns unprocessable_content status" do
        expect do
          post targets_path, params: invalid_json_params, as: :json
        end.not_to change(Target, :count)

        expect(response).to have_http_status(:unprocessable_content)
        json_response = response.parsed_body
        expect(json_response["errors"]).to include("Name can't be blank")
      end
    end
  end

  describe "PATCH /targets/:id (update)" do
    context "with valid parameters (JSON format)" do
      let(:update_params) do
        {
          target: {
            name: "Indeed Updated",
            is_active: false,
            category_id: other_category.id,
            allow_query_strings: true
          }
        }
      end

      it "updates the target category, attributes, and returns no content status (204)" do
        patch target_path(target), params: update_params, as: :json

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty

        target.reload
        expect(target.name).to eq("Indeed Updated")
        expect(target.is_active).to be_falsey
        expect(target.category_id).to eq(other_category.id)
        expect(target.allow_query_strings).to be_truthy
      end
    end

    context "with valid parameters (HTML format)" do
      let(:update_params_html) do
        {
          target: {
            name: "Indeed HTML Updated",
            category_id: category.id
          }
        }
      end

      it "updates the target and redirects to the edit page with notice" do
        patch target_path(target), params: update_params_html

        expect(response).to redirect_to(edit_target_path(target))

        follow_redirect!
        expect(response.body).to include("Target Indeed HTML Updated updated")

        target.reload
        expect(target.name).to eq("Indeed HTML Updated")
      end
    end

    context "with invalid parameters (HTML format)" do
      let(:invalid_update_params) do
        {
          target: {
            name: "",
            category_id: category.id
          }
        }
      end

      it "renders the edit template with unprocessable_content status" do
        patch target_path(target), params: invalid_update_params

        expect(response).to have_http_status(:unprocessable_content)

        target.reload
        expect(target.name).not_to eq("")
      end
    end
  end

  describe "DELETE /targets/:id (destroy)" do
    it "destroys the requested target and redirects to the category page" do
      expect do
        delete target_path(target)
      end.to change(Target, :count).by(-1)

      expect(response).to redirect_to(category_path(category))

      follow_redirect!
      expect(response.body).to include("Target was removed.")
    end
  end
end
