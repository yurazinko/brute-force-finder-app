# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuickSearchJob, type: :job do
  describe "#perform" do
    it "delegates the ephemeral search to QuickSearch::Runner" do
      runner = instance_double(QuickSearch::Runner, call: true)
      allow(QuickSearch::Runner).to receive(:new).with(token: "a" * 32, user_id: 42).and_return(runner)

      described_class.new.perform("a" * 32, 42)

      expect(runner).to have_received(:call)
    end
  end
end
