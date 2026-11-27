# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::CountersRefreshScheduler, type: :service do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user) }

  it "schedules one delayed refresh per active debounce window" do
    redis = instance_double(Redis)
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(SecureRandom).to receive(:hex).with(16).and_return("token-1")
    allow(redis).to receive(:incr).and_return(1)
    allow(redis).to receive(:expire)
    allow(redis).to receive(:set).and_return("OK")
    expect(SearchCampaigns::CountersRefreshJob).to receive(:perform_in)
      .with(1.second, search.id, user.id, "token-1")

    expect(described_class.schedule(search)).to be(true)
  end

  it "does not enqueue a second refresh while the debounce lock exists" do
    redis = instance_double(Redis)
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(SecureRandom).to receive(:hex).with(16).and_return("token-2")
    allow(redis).to receive(:incr).and_return(2)
    allow(redis).to receive(:expire)
    allow(redis).to receive(:set).and_return(nil)

    expect(SearchCampaigns::CountersRefreshJob).not_to receive(:perform_in)
    expect(described_class.schedule(search)).to be(false)
  end

  describe ".ensure_lock_ownership" do
    it "renews its own lease" do
      redis = instance_double(Redis)
      allow(Sidekiq).to receive(:redis).and_yield(redis)
      allow(redis).to receive(:get).with(described_class.lock_key(search.id)).and_return("token-1")
      expect(redis).to receive(:expire).with(described_class.lock_key(search.id), described_class::LOCK_TTL)
                                       .and_return(true)

      expect(described_class.ensure_lock_ownership(search.id, "token-1")).to be(true)
    end

    it "reacquires an expired lease only if no newer job owns it" do
      redis = instance_double(Redis)
      allow(Sidekiq).to receive(:redis).and_yield(redis)
      allow(redis).to receive(:get).with(described_class.lock_key(search.id)).and_return(nil)
      expect(redis).to receive(:set).with(
        described_class.lock_key(search.id), "token-1", nx: true, ex: described_class::LOCK_TTL
      ).and_return("OK")

      expect(described_class.ensure_lock_ownership(search.id, "token-1")).to be(true)
    end

    it "does not overwrite a newer job's lock token" do
      redis = instance_double(Redis)
      allow(Sidekiq).to receive(:redis).and_yield(redis)
      allow(redis).to receive(:get).with(described_class.lock_key(search.id)).and_return("token-2")
      expect(redis).not_to receive(:set)

      expect(described_class.ensure_lock_ownership(search.id, "token-1")).to be(false)
    end
  end
end
