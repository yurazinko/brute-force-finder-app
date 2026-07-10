# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Results", type: :request do
  let(:category) { Category.create!(name: "HR Tech") }
  let(:target) { Target.create!(category: category, name: "Lever", domain: "lever.co") }

  let(:search) do
    Search.create!(
      title: "Ruby Remote Jobs",
      query_conditions: "ruby remote",
      status: "pending",
      show_acknowledged: false
    )
  end

  let!(:result) do
    Result.create!(
      search: search,
      title: "Senior Backend Developer",
      url: "https://lever.co/jobs/1",
      url_hash: SecureRandom.hex(10),
      status: "unread",
      acknowledged: false
    )
  end

  describe "GET /results (index)" do
    context "when viewing globally (no search_id context)" do
      it "returns a successful HTML response" do
        get results_path
        expect(response).to have_http_status(:ok)
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

        expect(response.body).not_to include("results_pool_list")
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
end
