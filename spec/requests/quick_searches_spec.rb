# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Quick searches", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }
  let(:token) { SecureRandom.hex(16) }
  let(:quick_search_data) do
    {
      "token" => token,
      "user_id" => nil,
      "query" => "Ruby on Rails",
      "status" => "completed",
      "message" => "Search complete — 1 results found.",
      "active_engine" => nil,
      "results_count" => 1,
      "verification_total_count" => 0,
      "verification_completed_count" => 0
    }
  end

  describe "GET /" do
    it "renders the quick-search form without authentication" do
      get root_path

      expect(response).to have_http_status(:ok)
      assert_select "form[action='#{quick_searches_path}']"
      assert_select "input[name='query']"
      assert_select "input[type='submit'][value='🔍 Search']"
    end

    it "loads token-addressed transient results without requiring a signed-in user" do
      allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search_data)
      allow(QuickSearch::Store).to receive(:results).with(token).and_return(
        [
          {
            "url" => "https://example.com/jobs",
            "url_hash" => "abc",
            "title" => "Rails job",
            "engine" => "SearXNG",
            "relevance_score" => 80,
            "matched_keywords" => %w[Ruby Rails],
            "verification_status" => "verified"
          }
        ]
      )

      get root_path(quick_search: token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ruby on Rails", "Rails job", "Save as campaign")
      expect(response.body).not_to include("Move to Trash", "Configure")
      assert_select "#quick_result_abc[data-controller='read-status']"
      assert_select "#quick_result_abc a[data-action*='auxclick->read-status#markAsRead']"
      assert_select "#quick_result_abc a[data-read-url='#{mark_as_read_quick_search_path(token, url_hash: 'abc')}']"
    end

    it "restores the most recent search from the browser session when root is opened without a token" do
      allow(SecureRandom).to receive(:hex).with(16).and_return(token)
      allow(QuickSearch::Store).to receive(:create!)
      allow(QuickSearchJob).to receive(:perform_async)
      allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search_data)
      allow(QuickSearch::Store).to receive(:results).with(token).and_return([])

      post quick_searches_path, params: { query: "Ruby on Rails" }
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ruby on Rails", "Clear results")
      expect(QuickSearch::Store).to have_received(:fetch).with(token)
    end

    it "renders a clean page and forgets the token after its Redis entry expires" do
      allow(SecureRandom).to receive(:hex).with(16).and_return(token)
      allow(QuickSearch::Store).to receive(:create!)
      allow(QuickSearchJob).to receive(:perform_async)
      allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(nil)

      post quick_searches_path, params: { query: "Ruby on Rails" }
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Rails job", "Save as campaign", "Clear results")
      assert_select "input[name='query'][value='']"

      # The expired token must be removed, so another visit should not call Redis again.
      get root_path
      expect(QuickSearch::Store).to have_received(:fetch).with(token).once
    end
  end

  it "renders already-read quick-search results dimmed" do
    allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search_data)
    allow(QuickSearch::Store).to receive(:results).with(token).and_return(
      [
        {
          "url" => "https://example.com/read-job",
          "url_hash" => "read-hash",
          "title" => "Already viewed Rails job",
          "status" => "watched",
          "acknowledged" => true,
          "relevance_score" => 80,
          "matched_keywords" => ["Ruby"],
          "verification_status" => "verified"
        }
      ]
    )

    get root_path(quick_search: token)

    expect(response).to have_http_status(:ok)
    assert_select "#quick_result_read-hash.opacity-50"
  end

  describe "POST /quick_searches" do
    before do
      allow(QuickSearch::Store).to receive(:create!)
      allow(QuickSearchJob).to receive(:perform_async).and_return("quick-search-job-id")
    end

    it "accepts a guest search and enqueues it immediately without creating campaign records" do
      expect do
        post quick_searches_path, params: { query: "Ruby on Rails jobs" }
      end.not_to change(Search, :count)

      expect(QuickSearch::Store).to have_received(:create!).with(
        token: kind_of(String), user_id: nil, query: "Ruby on Rails jobs"
      )
      expect(QuickSearchJob).to have_received(:perform_async).with(kind_of(String), nil)
      expect(response).to have_http_status(:see_other)
      expect(response.location).to include("quick_search=")
    end

    it "uses the signed-in user's ID when available" do
      sign_in user
      post quick_searches_path, params: { query: "Rails jobs" }

      expect(QuickSearch::Store).to have_received(:create!).with(
        token: kind_of(String), user_id: user.id, query: "Rails jobs"
      )
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

  describe "GET /quick_searches/:token/save_as_campaign" do
    before do
      allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search_data)
    end

    it "stores the campaign form as the post-login destination for a guest" do
      get save_as_campaign_quick_search_path(token)

      expect(response).to redirect_to(new_user_session_path)
      expect(session["user_return_to"]).to eq(new_search_path(quick_search_token: token))
    end

    it "sends an authenticated user straight to the campaign form" do
      sign_in user
      get save_as_campaign_quick_search_path(token)

      expect(response).to redirect_to(new_search_path(quick_search_token: token))
    end
  end

  describe "PATCH /quick_searches/:token/mark_as_read" do
    it "marks a transient result as watched in the current quick-search session" do
      allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search_data)
      allow(QuickSearch::Store).to receive(:results).with(token).and_return([])
      get root_path(quick_search: token)

      expect(QuickSearch::Store).to receive(:update_result!).with(
        token,
        url_hash: "result-hash",
        attributes: { status: "watched", acknowledged: true }
      ).and_return({ "status" => "watched", "acknowledged" => true })

      patch mark_as_read_quick_search_path(token, url_hash: "result-hash")

      expect(response).to have_http_status(:no_content)
    end

    it "rejects updates for a token that is not stored in the browser session" do
      allow(QuickSearch::Store).to receive(:update_result!)

      patch mark_as_read_quick_search_path(token, url_hash: "result-hash")

      expect(response).to have_http_status(:not_found)
      expect(QuickSearch::Store).not_to have_received(:update_result!)
    end
  end

  describe "DELETE /quick_searches/clear" do
    it "clears the current token from Redis and the browser session" do
      allow(SecureRandom).to receive(:hex).with(16).and_return(token)
      allow(QuickSearch::Store).to receive(:create!)
      allow(QuickSearchJob).to receive(:perform_async)
      allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search_data)
      expect(QuickSearch::Store).to receive(:clear!).with(token)

      post quick_searches_path, params: { query: "Ruby on Rails" }
      delete clear_quick_searches_path

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(root_path)

      # A subsequent root request has no token in the browser session.
      get root_path
      expect(QuickSearch::Store).not_to have_received(:fetch).with(token)
    end
  end

  describe "GET /searches/new from a quick search" do
    it "prefills the campaign title and exact-quoted dork-builder value" do
      sign_in user
      allow(QuickSearch::Store).to receive(:fetch).with(token).and_return(quick_search_data)

      get new_search_path(quick_search_token: token)

      expect(response).to have_http_status(:ok)
      assert_select "input[name='search[title]']" do |elements|
        expect(elements.first["value"]).to eq("Search for Ruby on Rails")
      end

      builder = css_select("[data-react-portal-initial-value-value]").first
      expect(builder["data-react-portal-initial-value-value"]).to eq('"Ruby" "on" "Rails"')
      assert_select "textarea[data-react-portal-fallback]", text: '"Ruby" "on" "Rails"'
      assert_select "a[href='#{root_path(quick_search: token)}']", text: /Back to Quick Search Results/
    end
  end
end
