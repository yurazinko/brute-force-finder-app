# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::LifecycleNotifier, type: :service do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user) }
  let!(:result) { create(:result, search: search) }
  let(:counts) { double(unread: 2, interesting: 1, watched: 3, garbage: 0) }

  it "sends a batch of new result cards in one Turbo Stream render" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_render_to).with(
      search, :results,
      template: "searches/broadcast_new_results",
      assigns: { search: search, new_results: [result] }
    )

    described_class.broadcast_new_results(search, [result])
  end

  it "sends all counters in one Turbo Stream render" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_render_to).with(
      search, :results,
      template: "searches/broadcast_counters",
      assigns: { counts: counts }
    )

    described_class.broadcast_counters(search, counts)
  end
end
