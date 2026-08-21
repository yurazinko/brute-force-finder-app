# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchEngines::Searxng::Api::TorClient, type: :service do
  let(:query) { 'site:lever.co "ruby"' }
  let(:urls_env) { "http://searxng_1:8080,http://searxng_2:8080" }
  let(:instance1) { "http://searxng_1:8080" }
  let(:instance2) { "http://searxng_2:8080" }

  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/1")) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
    redis.flushdb

    stub_const("ENV", ENV.to_h.merge("SEARXNG_URLS" => urls_env))
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:info)
  end

  after do
    redis.flushdb
  end

  describe ".search" do
    it "instantiates the client and calls execute" do
      client_instance = instance_double(described_class, execute: { success: true, data: [] })
      allow(described_class).to receive(:new).with(query, {}).and_return(client_instance)

      described_class.search(query)

      expect(client_instance).to have_received(:execute)
    end
  end

  describe "#execute" do
    context "when query is blank" do
      it "returns success immediately without checking Redis or making HTTP requests" do
        client = described_class.new("   ")

        expect(client.execute).to eq({ data: [], success: true })
        expect(WebMock).not_to have_requested(:get, /.*/)
      end
    end

    context "when the request is successful (status 200)" do
      let(:mock_response_body) do
        {
          "results" => [
            { "url" => "https://lever.co/job1", "title" => "Ruby Developer", "content" => "Ctx" },
            { "url" => "https://lever.co/job2", "title" => "Senior RoR Engineer", "content" => "Ctx" },
            { "url" => "https://lever.co/job1", "title" => "Duplicate", "content" => "Ctx" }
          ],
          "unresponsive_engines" => []
        }.to_json
      end

      before do
        stub_request(:get, %r{searxng_\d:8080/search})
          .with(query: hash_including(q: query))
          .to_return(status: 200, body: mock_response_body)
      end

      it "returns unique results slicing only url, title, and content" do
        expected_result = {
          success: true,
          data: [
            { "url" => "https://lever.co/job1", "title" => "Ruby Developer", "content" => "Ctx" },
            { "url" => "https://lever.co/job2", "title" => "Senior RoR Engineer", "content" => "Ctx" }
          ],
          failed_engines: []
        }

        expect(described_class.new(query).execute).to eq(expected_result)
      end

      it "enforces unique SOCKS credentials per request for circuit isolation" do
        allow(SecureRandom).to receive(:hex).with(8).and_return("mockedauth123")
        allow(described_class).to receive(:get).and_call_original

        described_class.new(query).execute

        expect(described_class).to have_received(:get).with(
          anything,
          hash_including(socks_username: "mockedauth123", socks_password: "mockedauth123")
        )
      end
    end

    context "when Round-Robin and Circuit Breaker triage triggers" do
      it "cycles through instances via Round-Robin" do
        client = described_class.new(query)
        allow(client).to receive(:next_available_instance).and_return(instance1, instance2)

        stub_request(:get, "#{instance1}/search").with(query: hash_including(q: query)).to_raise(Timeout::Error)
        stub_request(:get, "#{instance2}/search")
          .with(query: hash_including(q: query))
          .to_return(status: 200, body: { results: [] }.to_json)

        result = client.execute

        expect(result[:success]).to be(true)
        expect(redis.exists?("searxng:dead:#{instance1}")).to(satisfy { |v| v == true || v.to_i > 0 })
      end

      it "skips dead instances in the pool" do
        redis.setex("searxng:dead:#{instance1}", 60, "dead")

        stub_request(:get, "#{instance1}/search")
          .with(query: hash_including(q: query))
          .to_return(status: 200, body: { results: [] }.to_json)
        stub_request(:get, "#{instance2}/search")
          .with(query: hash_including(q: query))
          .to_return(status: 200, body: { results: [{ "url" => "https://ok.com" }] }.to_json)

        result = described_class.new(query).execute
        expect(result[:data]).to eq([{ "url" => "https://ok.com" }])
        expect(WebMock).not_to have_requested(:get, "#{instance1}/search")
      end

      it "returns an error if all instances in the pool are dead" do
        redis.setex("searxng:dead:#{instance1}", 60, "dead")
        redis.setex("searxng:dead:#{instance2}", 60, "dead")

        result = described_class.new(query).execute
        expect(result).to eq({ success: false, error: "All SearXNG instances are currently dead" })
      end
    end

    context "when hitting rate limits (HTTP 429)" do
      it "marks the instance as dead, logs error, and retries with the next one" do
        client = described_class.new(query)
        allow(client).to receive(:next_available_instance).and_return(instance1, instance2)

        stub_request(:get, "#{instance1}/search").with(query: hash_including(q: query)).to_return(status: 429)
        stub_request(:get, "#{instance2}/search")
          .with(query: hash_including(q: query))
          .to_return(status: 200, body: { results: [] }.to_json)

        result = client.execute

        expect(result[:success]).to be(true)
        expect(redis.exists?("searxng:dead:#{instance1}")).to(satisfy { |v| v == true || v.to_i > 0 })
        expect(Rails.logger).to have_received(:error).with(/Rate limit \(429\) hit on #{instance1}/)
      end
    end

    context "when a persistent network failure or max retries exhaust" do
      before do
        stub_request(:get, %r{searxng_\d:8080/search})
          .with(query: hash_including(q: query))
          .to_raise(Errno::ECONNREFUSED.new("Connection refused"))
      end

      it "exhausts all retries, marks instances dead, and returns fallback message" do
        result = described_class.new(query).execute

        expect(result).to eq({ success: false, error: "All SearXNG instances are currently dead" })
        expect(redis.exists?("searxng:dead:#{instance1}")).to(satisfy { |v| v == true || v.to_i > 0 })
        expect(redis.exists?("searxng:dead:#{instance2}")).to(satisfy { |v| v == true || v.to_i > 0 })
      end
    end

    context "when JSON parsing fails" do
      before do
        stub_request(:get, %r{searxng_\d:8080/search})
          .with(query: hash_including(q: query))
          .to_return(status: 200, body: "not-json")
      end

      it "exhausts retries and returns max attempts error" do
        result = described_class.new(query).execute

        expect(result).to eq({ error: "Failed after 3 attempts across multiple instances", success: false })
        expect(Rails.logger).to have_received(:error).with(%r{Malformed JSON from http://searxng_}).at_least(:once)
      end
    end
  end
end
