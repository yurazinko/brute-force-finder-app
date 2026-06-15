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
      it "updates the status and returns a turbo stream to remove the element" do
        expect {
          patch result_path(result),
                params: { status: "garbage" },
                as: :turbo_stream
        }.to change { result.reload.status }.from("unread").to("garbage")

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")

        expect(response.body).to include(%(<turbo-stream action="remove" target="result_#{result.id}"></turbo-stream>))
      end
    end

    context "with HTML format (Standard Fallback)" do
      it "updates the status and redirects back to the search campaign page" do
        expect {
          patch result_path(result),
                params: { status: "interesting" }
        }.to change { result.reload.status }.from("unread").to("interesting")

        expect(response).to redirect_to(search_path(search))

        follow_redirect!
        expect(response.body).to include("Ruby Remote Jobs")
      end
    end

    context "when update fails due to invalid parameters" do
      before do
        patch result_path(result), params: { status: "invalid_status_value" }
      end

      it "does not update the status and returns no content (or early returns)" do
        expect(result.reload.status).to eq("unread")
        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
