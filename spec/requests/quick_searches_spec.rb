# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Quick searches", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /" do
    it "renders the quick-search form as the home page" do
      get root_path

      expect(response).to have_http_status(:ok)
      assert_select "form[action='#{quick_searches_path}']"
      assert_select "input[name='query']"
      assert_select "input[type='submit'][value='Search']"
    end

    it "loads only the current user's transient results" do
      token = SecureRandom.hex(16)
      data = {
        "token" => token,
        "user_id" => user.id,
        "query" => "Ruby on Rails",
        "status" => "completed",
        "message" => "Search complete — 1 results found.",
        "active_engine" => nil,
        "results_count" => 1
      }
      allow(QuickSearch::Store).to receive(:fetch).with(token, user_id: user.id).and_return(data)
      allow(QuickSearch::Store).to receive(:results).with(token, user_id: user.id).and_return([
                                                                                                { "url" => "https://example.com/jobs", "url_hash" => "abc", "title" => "Rails job", "engine" => "YaCy" }
                                                                                              ])

      get root_path(quick_search: token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ruby on Rails", "Rails job", "Save as campaign")
      expect(response.body).not_to include("Move to Trash", "Configure")
    end
  end

  describe "POST /quick_searches" do
    before do
      allow(QuickSearch::Store).to receive(:create!)
      allow(QuickSearch::Store).to receive(:update!)
      allow(QuickSearchJob).to receive(:perform_async).and_return("quick-search-job-id")
    end

    it "stores an ephemeral search and enqueues its job immediately without creating campaign records" do
      expect do
        post quick_searches_path, params: { query: "Ruby on Rails jobs" }
      end.not_to change(Search, :count)

      expect(QuickSearch::Store).to have_received(:create!).with(
        token: kind_of(String), user_id: user.id, query: "Ruby on Rails jobs"
      )
      expect(QuickSearchJob).to have_received(:perform_async).with(kind_of(String), user.id)
      expect(response).to have_http_status(:see_other)
      expect(response.location).to include("quick_search=")
    end

    it "rejects blank queries without enqueuing a job" do
      post quick_searches_path, params: { query: "   " }

      expect(QuickSearchJob).not_to have_received(:perform_async)
      expect(response).to redirect_to(root_path)
    end

    it "rejects queries that exceed the maximum length" do
      post quick_searches_path, params: { query: "x" * (QuickSearch::Store::MAX_QUERY_LENGTH + 1) }

      expect(QuickSearchJob).not_to have_received(:perform_async)
      expect(response).to redirect_to(root_path)
    end
  end
end
