# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Unified target editor", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }
  let!(:category) { create(:category, user: user) }
  let!(:search) { create(:search, user: user) }

  before { sign_in user }

  describe "GET /targets/new" do
    it "renders the unified React editor and supports a category preselection" do
      get new_target_path(category_id: category.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="path-builder"')
      expect(response.body).to include('data-path-builder-mode-value="target"')
      expect(response.body).to include(category.id.to_s)
    end
  end

  describe "POST /targets.json" do
    it "creates a target without requiring path patterns" do
      expect do
        post targets_path(format: :json), params: {
          target: {
            name: "Workable",
            domain: "workable.com",
            category_id: category.id,
            is_active: true,
            allow_query_strings: false,
            search_ids: []
          }
        }, as: :json
      end.to change(Target, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("target", "domain")).to eq("workable.com")
    end

    it "attaches the target to selected searches by creating prompts" do
      post targets_path(format: :json), params: {
        target: {
          name: "Greenhouse",
          domain: "greenhouse.io",
          category_id: category.id,
          is_active: true,
          allow_query_strings: false,
          search_ids: [search.id]
        }
      }, as: :json

      expect(response).to have_http_status(:created)
      target = Target.find(response.parsed_body.dig("target", "id"))
      prompt = target.prompts.find_by!(search: search)
      expect(prompt.full_query_text).to eq("site:greenhouse.io #{search.query_conditions}")
    end
  end

  describe "PATCH /targets/:id.json" do
    let!(:target) { create(:target, category: category) }

    it "updates target settings and synchronizes selected search attachments" do
      patch target_path(target, format: :json), params: {
        target: {
          name: "Updated target",
          domain: target.domain,
          category_id: category.id,
          is_active: false,
          allow_query_strings: true,
          search_ids: [search.id]
        }
      }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(target.reload.name).to eq("Updated target")
      expect(target.is_active).to be(false)
      expect(target.allow_query_strings).to be(true)
      expect(target.prompts.where(search: search).count).to eq(1)
    end
  end
end
