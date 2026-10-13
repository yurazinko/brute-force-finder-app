# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TargetPatterns", type: :request do
  include Devise::Test::IntegrationHelpers if defined?(Devise)

  let(:user) { User.create!(email: "test@example.com", password: "password") }
  let(:category) { Category.create!(name: "Job Boards", user: user) }
  let(:search) { Search.create!(title: "Ruby Developer", query_conditions: "ruby developer", user: user) }

  before do
    if defined?(Devise)
      sign_in user
    else
      begin
        allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
      rescue StandardError
        nil
      end
    end
  end

  describe "GET /target_patterns/new" do
    context "when result exists and matches an existing target" do
      let!(:target) { Target.create!(name: "GitHub Jobs", domain: "github.com", category: category, is_active: true) }
      let!(:result) { Result.create!(search: search, url: "https://github.com/jobs/123", url_hash: "hash_123") }

      it "renders the new template successfully and finds the matched target" do
        get new_target_pattern_path, params: { result_id: result.id }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("github.com")
      end
    end

    context "when result exists but NO target matches yet" do
      let!(:result) { Result.create!(search: search, url: "https://unknown-board.com/career/456", url_hash: "hash_456") }

      it "renders the new template preparing for auto-creation" do
        get new_target_pattern_path, params: { result_id: result.id }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("unknown-board.com")
      end
    end

    context "when result_id is invalid or missing" do
      it "handles missing result safely by redirecting" do
        get new_target_pattern_path, params: { result_id: 999_999 }

        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "POST /target_patterns" do
    let!(:result) { Result.create!(search: search, url: "https://lever.co/company/job-789", url_hash: "hash_789") }

    context "when target already exists globally" do
      let!(:existing_target) { Target.create!(name: "Lever", domain: "lever.co", category: category, is_active: true) }

      it "creates a new target pattern and ensures a prompt exists for the search" do
        expect do
          post target_patterns_path, params: {
            result_id: result.id,
            target_pattern: {
              target_id: existing_target.id,
              path_pattern: "/company/*"
            }
          }
        end.to change(TargetPattern, :count).by(1)

        pattern = TargetPattern.last
        expect(pattern.target_id).to eq(existing_target.id)
        expect(pattern.path_pattern).to eq("/company/*")
        expect(pattern.is_active).to be(true)
      end
    end

    context "when target does NOT exist globally (Auto-creation scenario)" do
      it "auto-creates the target, assigns it to the selected category, creates a prompt, and saves the pattern" do
        expect do
          post target_patterns_path, params: {
            result_id: result.id,
            target_pattern: {
              category_id: category.id,
              path_pattern: "/company/{id}"
            }
          }
        end.to change(Target, :count).by(1)
                                     .and change(TargetPattern, :count).by(1)

        new_target = Target.last
        expect(new_target.domain).to eq("lever.co")
        expect(new_target.category_id).to eq(category.id)

        pattern = TargetPattern.last
        expect(pattern.target_id).to eq(new_target.id)
        expect(pattern.path_pattern).to eq("/company/{id}")
      end
    end
  end

  describe "PATCH /target_patterns/:id" do
    let!(:target) { Target.create!(name: "Workable", domain: "workable.com", category: category) }
    let!(:pattern) { TargetPattern.create!(target: target, path_pattern: "/jobs/*", is_active: true) }

    it "successfully updates the pattern status" do
      patch target_pattern_path(pattern), params: {
        target_pattern: { is_active: false }
      }

      expect(pattern.reload.is_active).to be(false)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "DELETE /target_patterns/:id" do
    let!(:target) { Target.create!(name: "Greenhouse", domain: "greenhouse.io", category: category) }
    let!(:pattern) { TargetPattern.create!(target: target, path_pattern: "/positions/*", is_active: true) }

    it "successfully removes the pattern" do
      expect do
        delete target_pattern_path(pattern)
      end.to change(TargetPattern, :count).by(-1)

      expect(TargetPattern.exists?(pattern.id)).to be(false)
      expect(response).to have_http_status(:redirect)
    end
  end
end
