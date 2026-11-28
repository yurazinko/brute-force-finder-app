# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::CountersRefreshJob, type: :job do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user) }
  let(:counts) { double(unread: 1, interesting: 0, watched: 0, garbage: 0) }

  it "recalculates and broadcasts counters once the debounce window elapses" do
    redis = double
    allow(redis).to receive(:get).with(SearchCampaigns::CountersRefreshScheduler.lock_key(search.id)).and_return("lock-token")
    allow(redis).to receive(:get).with(SearchCampaigns::CountersRefreshScheduler.generation_key(search.id)).and_return("4")
    allow(redis).to receive(:expire)
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(Search).to receive(:find_by).with(id: search.id, user_id: user.id).and_return(search)
    allow(Results::Counters).to receive(:calculate_filtered).and_return(counts)
    expect(redis).to receive(:expire).with(SearchCampaigns::CountersRefreshScheduler.lock_key(search.id), SearchCampaigns::CountersRefreshScheduler::LOCK_TTL).and_return(true)
    expect(SearchCampaigns::LifecycleNotifier).to receive(:broadcast_counters).with(search, counts)
    expect(redis).to receive(:call).with("EVAL", anything, "2", anything, anything, "lock-token", "4").and_return(0)

    described_class.new.perform(search.id, user.id, "lock-token")
  end
end
