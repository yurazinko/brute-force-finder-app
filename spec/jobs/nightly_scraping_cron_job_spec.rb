# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightlyScrapingCronJob, type: :job do
  describe "#perform" do
    let!(:completed_search) { create(:search, status: "completed") }
    let!(:failed_search)    { create(:search, status: "failed") }
    let!(:processing_search) { create(:search, status: "processing") }

    before do
      SearchActivationJob.jobs.clear
      allow(Rails.env).to receive(:development?).and_return(false)
    end

    it "triggers SearchActivationJob only for completed and failed searches" do
      expect do
        described_class.new.perform
      end.to change(SearchActivationJob.jobs, :size).by(2)

      enqueued_ids = SearchActivationJob.jobs.map { |j| j["args"].first }
      expect(enqueued_ids).to include(completed_search.id, failed_search.id)
      expect(enqueued_ids).not_to include(processing_search.id)
    end

    it "calculates delayed scheduling correctly" do
      described_class.new.perform

      first_job = SearchActivationJob.jobs.first
      expect(first_job["at"]).to be_present
      expect(first_job["at"]).to be > Time.current.to_f
    end
  end
end
