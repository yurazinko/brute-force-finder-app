# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::CountersRefreshJob, type: :job do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user) }
  let(:counts) { double(unread: 1, interesting: 0, watched: 0, garbage: 0) }

  it "recalculates and broadcasts counters once the debounce window elapses" do
    redis = instance_double(Redis, get: "4", eval: 0)
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(Search).to receive(:find_by).with(id: search.id, user_id: user.id).and_return(search)
    allow(Results::Counters).to receive(:calculate_filtered).and_return(counts)
    expect(SearchCampaigns::LifecycleNotifier).to receive(:broadcast_counters).with(search, counts)

    described_class.new.perform(search.id, user.id, "lock-token")
  end
end
