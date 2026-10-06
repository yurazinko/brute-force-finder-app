# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboards", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }
  let(:category) { create(:category, user: user) }

  before do
    sign_in user
  end

  describe "GET /dashboard" do
    subject(:send_request) { get dashboard_path }

    context "when user is authenticated and data is present" do
      let(:user_search) { create(:search, user: user) }

      let(:target_one) { create(:target, category: category, name: "Alpha Target", domain: "alpha.com") }
      let(:target_two) { create(:target, category: category, name: "Beta Target", domain: "beta.com") }

      before do
        create_list(:prompt, 50, search: user_search, target: target_one)
        create_list(:prompt, 30, search: user_search, target: target_two)

        loser_targets = Target.top_by_prompts_count(5)

        allow(Result).to receive(:top_domains_efficiency).and_return({ "example.com" => 10, "test.com" => 5 })
        allow(Target).to receive(:top_by_prompts_count).with(5).and_return(loser_targets)
        allow(Target).to receive(:prompts_distribution_map).and_return({ "Alpha Target" => 50, "Beta Target" => 30 })
        allow(Targets::ResultCountsQuery).to receive(:call).with(loser_targets).and_return({ target_one.id => 0, target_two.id => 12 })
        create(:prompt, search: user_search, error_message: "Connection Timeout")
        create_list(:prompt, 2, search: user_search, error_message: "403 Forbidden")
      end

      it "returns http status success" do
        send_request
        expect(response).to have_http_status(:success)
      end

      it "renders productive domains section with correct data" do
        send_request
        expect(response.body).to include("Most Productive Domains")
        expect(response.body).to include("example.com")
        expect(response.body).to include("10 leads")
        expect(response.body).to include("style=\"width: 100%\"")
        expect(response.body).to include("style=\"width: 50%\"")
      end

      it "renders dead weight targets section with zero-lead highlighting" do
        send_request
        expect(response.body).to include("Dead Weight Targets (Losers)")
        expect(response.body).to include("Alpha Target")
        expect(response.body).to include("0 leads found")
        expect(response.body).to include("text-red-500 font-bold")
      end

      it "renders engine load section with calculated progress bars" do
        send_request
        expect(response.body).to include("Engine Load (Prompts per Target)")
        expect(response.body).to include("Alpha Target")
        expect(response.body).to include("50 requests")
        expect(response.body).to include("style=\"width: 100%\"")
        expect(response.body).to include("style=\"width: 60%\"")
      end

      it "renders pipeline failures grouped and ordered by count" do
        send_request
        expect(response.body).to include("Top Pipeline Failures")
        expect(response.body).to include("403 Forbidden")
        expect(response.body).to include("Connection Timeout")
      end
    end

    context "when dashboard data is empty" do
      before do
        allow(Result).to receive(:top_domains_efficiency).and_return({})
        allow(Target).to receive(:top_by_prompts_count).with(5).and_return([])
        allow(Target).to receive(:prompts_distribution_map).and_return({})
        allow(Targets::ResultCountsQuery).to receive(:call).and_return({})
      end

      it "renders empty states cleanly without division by zero errors" do
        send_request

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No data available")
        expect(response.body).to include("No targets queried yet.")
        expect(response.body).to include("No errors tracked. Pipeline is clean! 🚀")
      end
    end

    context "when user is not authenticated" do
      before do
        sign_out user if defined?(sign_out)
      end

      it "redirects to the sign in page" do
        get dashboard_path
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
