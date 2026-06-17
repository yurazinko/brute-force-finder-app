# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Targets", type: :request do
  let!(:category) { Category.create!(name: "Job Boards") }
  let!(:target) { Target.create!(category: category, name: "Indeed", domain: "indeed.com", is_active: true) }

  before do
    host! "localhost"
    ActionController::Base.allow_forgery_protection = false
  end

  describe "POST /targets (create)" do
    context "with valid parameters" do
      let(:valid_params) do
        {
          target: {
            name: "LinkedIn",
            domain: "linkedin.com",
            is_active: true,
            category_id: category.id
          }
        }
      end

      it "creates a new Target and redirects to the category show page" do
        expect do
          post targets_path, params: valid_params
        end.to change(Target, :count).by(1)

        expect(response).to redirect_to(category_path(category))

        follow_redirect!
        expect(response.body).to include("Target LinkedIn added!")
      end
    end

    context "with invalid parameters" do
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
        expect(response.body).to include("Error:")
        expect(CGI.unescapeHTML(response.body)).to include("Error: Name can't be blank")
      end
    end
  end

  describe "PATCH /targets/:id (update)" do
    let(:update_params) do
      {
        target: {
          name: "Indeed Updated",
          is_active: false,
          category_id: category.id
        }
      }
    end

    it "updates the target and returns no content status (204)" do
      patch target_path(target), params: update_params, as: :json

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty

      target.reload
      expect(target.name).to eq("Indeed Updated")
      expect(target.is_active).to be_falsey
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
