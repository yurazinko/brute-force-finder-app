# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Results", type: :request do
  let(:category) { Category.create!(name: "HR Tech") }
  let(:target) { Target.create!(category: category, name: "Lever", domain: "lever.co") }

  let(:search) do
    Search.create!(
      title: "Ruby Remote Jobs",
      query_conditions: "ruby remote",
      status: "pending"
    )
  end

  let!(:result) do
    Result.create!(
      search: search,
      title: "Senior Backend Developer",
      url: "https://lever.co/jobs/1",
      url_hash: SecureRandom.hex(10),
      status: "unread"
    )
  end

  describe "PATCH /results/:id (update)" do
    context "with Turbo Stream format (JS/Async)" do
      context "when the new status matches the current tab" do
        it "updates the status and REPLACES the card element on the screen" do
          expect do
            patch result_path(result),
                  params: { status: "watched", current_tab: "watched", d: "7", format: :turbo_stream }
          end.to change { result.reload.status }.from("unread").to("watched")

          expect(response).to have_http_status(:ok)

          expect(response.body).to include(%(turbo-stream action="replace" target="result_#{result.id}"))
          expect(response.body).to include(%(turbo-stream action="update" target="counter_watched"))
          expect(response.body).to include(%(turbo-stream action="update" target="results_count"))
        end
      end

      context "when the new status differs from the current tab" do
        it "updates the status and REMOVES the card element from the screen" do
          expect do
            patch result_path(result),
                  params: { status: "garbage", current_tab: "unread", d: "1", format: :turbo_stream }
          end.to change { result.reload.status }.from("unread").to("garbage")

          expect(response).to have_http_status(:ok)

          expect(response.body).to include(%(turbo-stream action="remove" target="result_#{result.id}"))
          expect(response.body).to include(%(turbo-stream action="update" target="counter_garbage"))
          expect(response.body).to include(%(turbo-stream action="update" target="results_count"))
        end
      end
    end

    context "with HTML format (Standard Fallback)" do
      it "updates the status and redirects back preserving all active filters" do
        expect do
          patch result_path(result),
                params: { status: "interesting", current_tab: "unread", d: "30" }
        end.to change { result.reload.status }.from("unread").to("interesting")

        expect(response).to redirect_to(search_path(search, status: "unread", d: "30"))

        follow_redirect!
        expect(response.body).to include("Ruby Remote Jobs")
      end
    end

    context "when update fails or returns unless verified" do
      before do
        allow_any_instance_of(Result).to receive(:update).and_return(false)
        allow_any_instance_of(Result).to receive(:update!).and_return(false)

        patch result_path(result), params: { status: "unread", current_tab: "unread" }
      end

      it "early returns without modifying database state and redirects back" do
        expect(result.reload.status).to eq("unread")

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(search_path(search, status: "unread"))
      end
    end
  end
end
