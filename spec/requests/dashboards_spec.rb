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
      let(:target_one) { create(:target, category: category, name: "Alpha Target", domain: "alpha.com") }
      let(:target_two) { create(:target, category: category, name: "Beta Target", domain: "beta.com") }

      let(:productive_domains) do
        [
          { domain: "example.com", relevant_results_count: 10, total_relevance_score: 50, average_relevance_score: 5.0 },
          { domain: "test.com", relevant_results_count: 5, total_relevance_score: 12, average_relevance_score: 2.4 }
        ]
      end

      let(:loser_targets) do
        [
          Targets::LowYieldQuery::Stat.new(
            target: target_one, prompts_count: 50, relevant_results_count: 0, yield_percentage: 0.0
          ),
          Targets::LowYieldQuery::Stat.new(
            target: target_two, prompts_count: 30, relevant_results_count: 0, yield_percentage: 0.0
          )
        ]
      end

      before do
        allow(Result).to receive(:top_domains_efficiency)
          .with(hash_including(limit: 15)).and_return(productive_domains)
        allow(Targets::LowYieldQuery).to receive(:call)
          .with(hash_including(limit: 10)).and_return(loser_targets)
      end

      it "returns http status success" do
        send_request
        expect(response).to have_http_status(:success)
      end

      it "renders productive domains section with correct data" do
        send_request
        expect(response.body).to include("Most Productive Domains")
        expect(response.body).to include("example.com")
        expect(response.body).to include("test.com")
      end

      it "renders low-yield targets section correctly" do
        send_request
        expect(response.body).to include("Low-Yield Targets")
        expect(response.body).to include("Alpha Target")
        expect(response.body).to include("alpha.com")
        expect(response.body).to include("Beta Target")
        expect(response.body).to include("beta.com")
        expect(response.body).to include("0%")
      end
    end

    context "when dashboard data is empty" do
      before do
        allow(Result).to receive(:top_domains_efficiency).and_return([])
        allow(Targets::LowYieldQuery).to receive(:call).and_return([])
      end

      it "renders empty states cleanly" do
        send_request

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No relevant results found in the last 30 days.")
        expect(response.body).to include("No low-yield targets found for the last 30 days.")
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
