# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Results", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }
  let(:category) { Category.create!(name: "HR Tech") }
  let(:target) { Target.create!(category: category, name: "Lever", domain: "lever.co") }

  let(:search) do
    Search.create!(
      user: user,
      title: "Ruby Remote Jobs",
      query_conditions: "ruby remote",
      status: "pending",
      show_acknowledged: false,
      relevance_mode: "strict"
    )
  end

  let(:search2) do
    Search.create!(
      user: user,
      title: "Rails Senior Jobs",
      query_conditions: "rails senior",
      status: "pending",
      show_acknowledged: false
    )
  end

  let!(:result) do
    Result.create!(
      search: search,
      title: "Senior Backend Developer",
      url: "https://lever.co/jobs/1",
      url_hash: "shared_hash123",
      status: "unread",
      acknowledged: false,
      relevance_score: 150
    )
  end

  let!(:result2) do
    Result.create!(
      search: search,
      title: "Fullstack Engineer",
      url: "https://lever.co/jobs/2",
      url_hash: "shared_hash456",
      status: "unread",
      acknowledged: false,
      relevance_score: 120
    )
  end

  let!(:result3) do
    Result.create!(
      search: search,
      title: "Junior Developer",
      url: "https://lever.co/jobs/3",
      url_hash: "shared_hash789",
      status: "unread",
      acknowledged: false,
      relevance_score: 74
    )
  end

  let!(:other_search_result) do
    Result.create!(
      search: search2,
      title: "Senior Backend Developer (Other Search)",
      url: "https://lever.co/jobs/1",
      url_hash: "shared_hash123",
      status: "unread",
      acknowledged: false,
      relevance_score: 150
    )
  end

  before do
    sign_in user if respond_to?(:sign_in)
  end

  describe "GET /results (index)" do
    context "when viewing globally (no search_id context)" do
      it "returns a successful HTML response without Search-only bulk controls" do
        get results_path
        expect(response).to have_http_status(:ok)
        assert_select "#bulk_actions_top", 0
        assert_select "#bulk_actions_bottom", 0
      end
    end

    context "with a specific search_id context via Turbo Frame" do
      it "renders the template content successfully" do
        get results_path, params: { turbo_frame: "results_frame", search_id: search.id }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Ruby Remote Jobs")
      end
    end

    context "with a specific search_id context" do
      it "filters results by search scope successfully" do
        get results_path, params: { search_id: search.id }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Senior Backend Developer")
      end
    end
  end

  describe "GET /searches/:id" do
    it "renders all four bulk actions above and below the Search result list" do
      get search_path(search)

      expect(response).to have_http_status(:ok)
      assert_select "#bulk_actions_top", 1
      assert_select "#bulk_actions_bottom", 1
      assert_select "#bulk_actions_top form[data-turbo='false']", 4
      assert_select "#bulk_actions_bottom form[data-turbo='false']", 4
      assert_select "#bulk_actions_top select[data-bulk-actions-scope-select] option[value='visible']", 1
      assert_select "#bulk_actions_top select[data-bulk-actions-scope-select] option[value='all_matching']", 1
      assert_select "#bulk_actions_bottom select[data-bulk-actions-scope-select] option[value='visible']", 1
      assert_select "#bulk_actions_bottom select[data-bulk-actions-scope-select] option[value='all_matching']", 1
      assert_select "#bulk_actions_top button[disabled]", text: /Unread/
      assert_select "#bulk_actions_bottom button[disabled]", text: /Unread/
      %w[Reviewed Starred Trash].each do |label|
        assert_select "#bulk_actions_top button:not([disabled])", text: /#{Regexp.escape(label)}/
        assert_select "#bulk_actions_bottom button:not([disabled])", text: /#{Regexp.escape(label)}/
      end
      %w[Unread Reviewed Starred Trash].each do |label|
        assert_select "#bulk_actions_top button", text: /#{Regexp.escape(label)}/
        assert_select "#bulk_actions_bottom button", text: /#{Regexp.escape(label)}/
      end
    end

    it "disables the bulk action matching the currently selected tab" do
      tabs = {
        nil => "unread",
        "watched" => "watched",
        "interesting" => "interesting",
        "garbage" => "garbage"
      }
      bulk_containers = %w[bulk_actions_top bulk_actions_bottom]

      tabs.each do |tab_param, active_status|
        result.update!(status: active_status, acknowledged: active_status != "unread")
        get search_path(search, status: tab_param)

        expect(response).to have_http_status(:ok)

        bulk_containers.each do |container_id|
          forms = response.parsed_body.css("##{container_id} form")
          states = forms.to_h do |form|
            target = form.at_css('input[name="target_status"]')&.[]("value")
            [target, form.at_css("button")&.key?("disabled")]
          end

          expect(states).to eq(
            "unread" => (active_status == "unread"),
            "watched" => (active_status == "watched"),
            "interesting" => (active_status == "interesting"),
            "garbage" => (active_status == "garbage")
          )
        end
      end
    end

    it "refreshes both bulk forms to the less-relevant bucket without replacing the results frame" do
      get search_path(search, format: :turbo_stream, show_less_relevant: "true")

      expect(response).to have_http_status(:ok)
      assert_select "turbo-stream[action='replace'][target='bulk_actions_top']"
      assert_select "turbo-stream[action='replace'][target='bulk_actions_bottom']"
      assert_select "turbo-stream[action='replace'][target='results_pool']", 0
      expect(response.body.scan('name="show_less_relevant" value="true"').size).to eq(8)
    end
  end

  describe "PATCH /results/:id (update)" do
    context "with Turbo Stream format (JS/Async)" do
      it "removes the updated card from DOM and updates counters without appending anything" do
        expect do
          patch result_path(result, format: :turbo_stream),
                params: { result: { status: "watched" }, status: "unread", current_dom_count: "10" }
        end.to change { result.reload.status }.from("unread").to("watched")

        expect(response).to have_http_status(:ok)

        assert_select "turbo-stream[action='remove'][target='result_#{result.id}']"
        assert_select "turbo-stream[action='replace'][target='search_tabs_navigation']"
      end

      it "isolates acknowledged status updates to the specific search scope" do
        expect(other_search_result.acknowledged).to be false

        patch result_path(result, format: :turbo_stream),
              params: { result: { status: "watched" }, status: "unread" }

        expect(response).to have_http_status(:ok)
        expect(result.reload.acknowledged).to be true

        expect(other_search_result.reload.acknowledged).to be false
      end
    end

    context "with HTML format (Standard Fallback)" do
      context "inside a specific search context" do
        it "updates the status and redirects to search show view" do
          expect do
            patch result_path(result),
                  params: { result: { status: "interesting" }, status: "unread", d: "30", search_id: search.id }
          end.to change { result.reload.status }.from("unread").to("interesting")

          expect(response).to redirect_to(search_path(search, status: "unread", d: "30"))
        end
      end

      context "inside the global index context" do
        it "updates the status and redirects to global results path" do
          expect do
            patch result_path(result),
                  params: { result: { status: "garbage" }, status: "unread", d: "1" }
          end.to change { result.reload.status }.from("unread").to("garbage")

          expect(response).to redirect_to(results_path(status: "unread", d: "1"))
        end
      end
    end

    context "when database validation fails" do
      before do
        allow_any_instance_of(Result).to receive(:update).and_return(false)
      end

      it "returns unprocessable_content for turbo_stream requests" do
        patch result_path(result, format: :turbo_stream), params: { result: { status: "invalid" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns unprocessable_content response for HTML format" do
        patch result_path(result), params: { result: { status: "invalid" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH /results/bulk_update" do
    it "does not allow bulk updates from the global results feed" do
      patch bulk_update_results_path,
            params: { target_status: "watched", visible_ids: [result.id] }

      expect(response).to redirect_to(results_path)
      expect(result.reload.status).to eq("unread")
    end

    it "updates only currently eligible visible results and redirects to a clean search URL" do
      patch bulk_update_results_path,
            params: {
              search_id: search.id,
              target_status: "watched",
              visible_ids: [result.id, result2.id, result3.id],
              d: "week",
              q: "lever",
              show_less_relevant: "false"
            }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(search_path(search, d: "week", q: "lever", show_less_relevant: "false"))

      expect(result.reload.status).to eq("watched")
      expect(result.reload.acknowledged).to be(true)
      expect(result2.reload.status).to eq("watched")
      expect(result2.reload.acknowledged).to be(true)

      # Strict mode's normal bucket excludes the partial result (score 90).
      expect(result3.reload.status).to eq("unread")
      expect(result3.reload.acknowledged).to be(false)

      location_query = Rack::Utils.parse_nested_query(URI(response.location).query)
      expect(location_query).not_to have_key("target_status")
      expect(location_query).not_to have_key("visible_ids")
      expect(location_query).not_to have_key("search_id")
    end

    it "updates every matching result in the current tab when all_relevant scope is selected" do
      patch bulk_update_results_path,
            params: {
              search_id: search.id,
              target_status: "watched",
              bulk_scope: "all_matching",
              visible_ids: [result.id],
              d: "week",
              q: "lever"
            }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(search_path(search, d: "week", q: "lever", bulk_scope: "all_matching"))

      expect(result.reload.status).to eq("watched")
      expect(result2.reload.status).to eq("watched")
      expect(result3.reload.status).to eq("unread")
      expect(other_search_result.reload.status).to eq("unread")
    end

    it "updates all results in the selected less-relevant bucket, not the normal bucket" do
      patch bulk_update_results_path,
            params: {
              search_id: search.id,
              target_status: "garbage",
              bulk_scope: "all_matching",
              show_less_relevant: "true"
            }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(search_path(search, show_less_relevant: "true", bulk_scope: "all_matching"))
      expect(result.reload.status).to eq("unread")
      expect(result2.reload.status).to eq("unread")
      expect(result3.reload.status).to eq("garbage")
      expect(result3.reload.acknowledged).to be(true)
    end

    it "rejects an unknown bulk scope without changing any result" do
      patch bulk_update_results_path,
            params: {
              search_id: search.id,
              target_status: "watched",
              bulk_scope: "everything_in_database",
              visible_ids: [result.id, result2.id]
            }

      expect(response).to have_http_status(:see_other)
      expect(result.reload.status).to eq("unread")
      expect(result2.reload.status).to eq("unread")
    end

    it "can move currently visible results back to Inbox and clears acknowledged" do
      result.update!(status: "watched", acknowledged: true)

      patch bulk_update_results_path,
            params: {
              search_id: search.id,
              target_status: "unread",
              status: "watched",
              visible_ids: [result.id]
            }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(search_path(search, status: "watched"))
      expect(result.reload.status).to eq("unread")
      expect(result.acknowledged).to be(false)
    end

    it "updates only the less-relevant bucket after Show results below this threshold" do
      patch bulk_update_results_path,
            params: {
              search_id: search.id,
              target_status: "garbage",
              show_less_relevant: "true",
              visible_ids: [result.id, result3.id]
            }

      expect(response).to have_http_status(:see_other)
      expect(result.reload.status).to eq("unread")
      expect(result3.reload.status).to eq("garbage")
      expect(result3.reload.acknowledged).to be(true)
    end

    it "does not update results from another search even when their IDs are submitted" do
      patch bulk_update_results_path,
            params: {
              search_id: search.id,
              target_status: "interesting",
              status: "unread",
              visible_ids: [other_search_result.id]
            }

      expect(response).to have_http_status(:see_other)
      expect(other_search_result.reload.status).to eq("unread")
    end

    it "ignores invalid target status and redirects without leaking bulk params" do
      patch bulk_update_results_path,
            params: {
              search_id: search.id,
              target_status: "invalid_status",
              visible_ids: [result.id]
            }

      expect(response).to have_http_status(:see_other)
      expect(result.reload.status).to eq("unread")
      location_query = Rack::Utils.parse_nested_query(URI(response.location).query)
      expect(location_query).not_to have_key("target_status")
      expect(location_query).not_to have_key("visible_ids")
    end
  end
end
