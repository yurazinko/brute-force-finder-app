# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe NightlyScrapingCronJob, type: :job do
  describe "#perform" do
    let(:user) { User.create!(username: "cron_test@example.com", password: "password123") }

    let!(:completed_search)  { create(:search, user: user, status: "completed") }
    let!(:failed_search)     { create(:search, user: user, status: "failed") }
    let!(:processing_search) { create(:search, user: user, status: "processing") }
    let!(:paused_search)     { create(:search, user: user, status: "paused") }

    before do
      Sidekiq::Testing.fake!
      SearchActivationJob.jobs.clear
      allow(Rails.env).to receive(:development?).and_return(false)
    end

    it "triggers SearchActivationJob only for completed, processing and failed searches" do
      expect do
        described_class.new.perform
      end.to change(SearchActivationJob.jobs, :size).by(3)

      enqueued_ids = SearchActivationJob.jobs.map { |j| j["args"].first }
      expect(enqueued_ids).to include(completed_search.id, processing_search.id, failed_search.id)
      expect(enqueued_ids).not_to include(paused_search.id)
    end

    it "calculates delayed scheduling correctly" do
      described_class.new.perform

      first_job = SearchActivationJob.jobs.first
      expect(first_job["at"]).to be_present
      expect(first_job["at"]).to be > Time.current.to_f
    end
  end
end
