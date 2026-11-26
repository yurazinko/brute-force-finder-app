# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::DomainThrottle do
  let(:redis) { instance_double(Redis) }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis)
  end

  it "acquires a domain throttle atomically with Redis SET NX EX" do
    expect(redis).to receive(:set).with(
      "domain_throttle:example.com", "1", nx: true, ex: 3
    ).and_return("OK")

    expect(described_class.acquire?("Example.com")).to be(true)
  end

  it "returns false when another worker already holds the throttle" do
    allow(redis).to receive(:set).and_return(nil)

    expect(described_class.acquire?("example.com")).to be(false)
  end

  it "rejects an empty domain or non-positive TTL" do
    expect { described_class.acquire?(" ") }.to raise_error(ArgumentError, /Domain is required/)
    expect { described_class.acquire?("example.com", expires_in: 0.seconds) }
      .to raise_error(ArgumentError, /TTL must be positive/)
  end
end
