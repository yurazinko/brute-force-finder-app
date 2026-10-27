# frozen_string_literal: true

require "rails_helper"

RSpec.describe Alerts::DeadTargetsChecker, type: :service do
  let(:user) { create(:user) }
  let!(:category) { create(:category, user: user) }
  subject(:checker) { described_class.new(user) }

  before do
    Rails.cache.delete("user:#{user.id}:has_dead_targets")
  end

  describe "#show_alert?" do
    context "when the alert is dismissed in cache" do
      before do
        allow(Rails.cache).to receive(:exist?).with("user:#{user.id}:dismissed_dead_targets").and_return(true)
      end

      it "returns false even if dead targets exist" do
        allow(Targets::LowYieldQuery).to receive(:call).and_return([double(:stat)])
        expect(checker.show_alert?).to be false
      end
    end

    context "when the alert is not dismissed and dead targets exist" do
      before do
        allow(Rails.cache).to receive(:exist?).with("user:#{user.id}:dismissed_dead_targets").and_return(false)
        allow(Targets::LowYieldQuery).to receive(:call).and_return([double(:stat)])
      end

      it "returns true" do
        expect(checker.show_alert?).to be true
      end
    end

    context "when the alert is not dismissed and no dead targets exist" do
      before do
        allow(Rails.cache).to receive(:exist?).with("user:#{user.id}:dismissed_dead_targets").and_return(false)
        allow(Targets::LowYieldQuery).to receive(:call).and_return([])
      end

      it "returns false" do
        expect(checker.show_alert?).to be false
      end
    end
  end
end
