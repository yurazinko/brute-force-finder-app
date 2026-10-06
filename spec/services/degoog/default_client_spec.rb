# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchEngines::Degoog::Api::DefaultClient, type: :service do
  let(:query) { 'site:indeed.com/viewjob "ruby"' }
  let(:urls_env) { "http://degoog_1:4444,http://degoog_2:4444" }
  let(:instance1) { "http://degoog_1:4444" }
  let(:instance2) { "http://degoog_2:4444" }

  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/1")) }
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(Rails).to receive(:cache).and_return(memory_store)
    redis.flushdb
    memory_store.clear

    stub_const("ENV", ENV.to_h.merge("DEGOOG_URLS" => urls_env))
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:info)
  end

  after do
    redis.flushdb
    memory_store.clear
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
        expect(WebMock).not_to have_requested(:post, /.*/)
        expect(WebMock).not_to have_requested(:get, /.*/)
      end
    end

    context "when the request is successful (status 200)" do
      let(:extensions_response) do
        {
          "engines" => [
            { "id" => "degoog-org-official-extensions-bing-engine" },
            { "id" => "degoog-org-official-extensions-google-engine" }
          ]
        }.to_json
      end

      let(:mock_response_body) do
        {
          "results" => [
            {
              "url" => "https://indeed.com/viewjob?id=1",
              "title" => "Ruby Developer",
              "content" => "Ctx",
              "source" => "bing"
            },
            {
              "url" => "https://indeed.com/viewjob?id=2",
              "title" => "Senior RoR Engineer",
              "snippet" => "Ctx",
              "sources" => %w[google brave]
            },
            {
              "url" => "https://indeed.com/viewjob?id=1",
              "title" => "Duplicate",
              "content" => "Ctx"
            }
          ]
        }.to_json
      end

      before do
        stub_request(:get, %r{degoog_\d:4444/api/extensions\?type=engine})
          .to_return(status: 200, body: extensions_response, headers: { "Content-Type" => "application/json" })

        stub_request(:post, %r{degoog_\d:4444/api/search})
          .with(
            body: hash_including(
              "query" => 'site:indeed.com "ruby"',
              "type" => "web",
              "page" => 1,
              "time" => "any",
              "engines" => %w[
                degoog-org-official-extensions-bing-engine
                degoog-org-official-extensions-google-engine
              ]
            )
          )
          .to_return(status: 200, body: mock_response_body)
      end

      it "sanitizes query, fetches engines, parses response, and formats engine labels" do
        expected_result = {
          success: true,
          data: [
            {
              "url" => "https://indeed.com/viewjob?id=1",
              "title" => "Ruby Developer",
              "content" => "Ctx",
              "engine" => "Degoog/bing"
            },
            {
              "url" => "https://indeed.com/viewjob?id=2",
              "title" => "Senior RoR Engineer",
              "content" => "Ctx",
              "engine" => "Degoog/Google, Brave"
            }
          ]
        }

        expect(described_class.new(query).execute).to eq(expected_result)
      end

      it "caches active engines to avoid repeated GET calls" do
        allow_any_instance_of(described_class).to receive(:next_available_instance).and_return(instance1)

        described_class.new(query).execute
        described_class.new(query).execute

        expect(WebMock).to have_requested(:get, "#{instance1}/api/extensions?type=engine").once
      end

      it "passes authorization header if DEGOOG_API_KEY is present" do
        stub_const("ENV", ENV.to_h.merge("DEGOOG_API_KEY" => "secret_key_123"))

        described_class.new(query).execute

        expect(WebMock).to have_requested(:post, %r{degoog_\d:4444/api/search})
          .with(headers: { "Authorization" => "Bearer secret_key_123" })
      end
    end

    context "when /api/extensions fails or returns no engines" do
      let(:mock_search_body) { { "results" => [] }.to_json }

      it "falls back to default FALLBACK_ENGINES list when response is not successful" do
        stub_request(:get, %r{degoog_\d:4444/api/extensions\?type=engine})
          .to_return(status: 500)

        stub_request(:post, %r{degoog_\d:4444/api/search})
          .with(body: hash_including("engines" => described_class::FALLBACK_ENGINES))
          .to_return(status: 200, body: mock_search_body)

        result = described_class.new(query).execute

        expect(result[:success]).to be(true)
      end

      it "logs warning when request raises an exception" do
        stub_request(:get, %r{degoog_\d:4444/api/extensions\?type=engine})
          .to_raise(StandardError.new("Network Error"))

        stub_request(:post, %r{degoog_\d:4444/api/search})
          .with(body: hash_including("engines" => described_class::FALLBACK_ENGINES))
          .to_return(status: 200, body: mock_search_body)

        result = described_class.new(query).execute

        expect(result[:success]).to be(true)
        expect(Rails.logger).to have_received(:warn).with(%r{Failed to fetch engines from http://degoog_})
      end
    end

    context "when Round-Robin and Circuit Breaker triage triggers" do
      before do
        stub_request(:get, %r{degoog_\d:4444/api/extensions\?type=engine})
          .to_return(status: 200, body: { "engines" => [] }.to_json)
      end

      it "cycles through instances via Round-Robin" do
        client = described_class.new(query)
        allow(client).to receive(:next_available_instance).and_return(instance1, instance2)

        stub_request(:post, "#{instance1}/api/search").to_raise(Timeout::Error)
        stub_request(:post, "#{instance2}/api/search").to_return(status: 200, body: { "results" => [] }.to_json)

        result = client.execute

        expect(result[:success]).to be(true)
        expect(redis.exists?("degoog:dead:#{instance1}")).to(satisfy { |v| v == true || v.to_i > 0 })
      end

      it "skips dead instances in the pool" do
        redis.setex("degoog:dead:#{instance1}", 60, "dead")

        stub_request(:post, "#{instance2}/api/search")
          .to_return(status: 200, body: { "results" => [{ "url" => "https://ok.com" }] }.to_json)

        result = described_class.new(query).execute

        expect(result[:data]).to eq(
          [
            { "url" => "https://ok.com", "title" => nil, "content" => "", "engine" => "Degoog" }
          ]
        )
        expect(WebMock).not_to have_requested(:post, "#{instance1}/api/search")
      end

      it "returns an error if all instances in the pool are dead" do
        redis.setex("degoog:dead:#{instance1}", 60, "dead")
        redis.setex("degoog:dead:#{instance2}", 60, "dead")

        result = described_class.new(query).execute
        expect(result).to eq({ success: false, error: "All Degoog instances are currently dead" })
      end
    end

    context "when hitting rate limits (HTTP 429)" do
      before do
        stub_request(:get, %r{degoog_\d:4444/api/extensions\?type=engine})
          .to_return(status: 200, body: { "engines" => [] }.to_json)
      end

      it "marks the instance as dead, logs error, and retries with the next one" do
        client = described_class.new(query)
        allow(client).to receive(:next_available_instance).and_return(instance1, instance2)

        stub_request(:post, "#{instance1}/api/search").to_return(status: 429)
        stub_request(:post, "#{instance2}/api/search").to_return(status: 200, body: { "results" => [] }.to_json)

        result = client.execute

        expect(result[:success]).to be(true)
        expect(redis.exists?("degoog:dead:#{instance1}")).to(satisfy { |v| v == true || v.to_i > 0 })
        expect(Rails.logger).to have_received(:error).with(/Rate limit hit on #{instance1}/)
      end
    end

    context "when unauthorized (HTTP 401)" do
      before do
        stub_request(:get, %r{degoog_\d:4444/api/extensions\?type=engine})
          .to_return(status: 200, body: { "engines" => [] }.to_json)

        stub_request(:post, %r{degoog_\d:4444/api/search})
          .to_return(status: 401)
      end

      it "exhausts attempts and returns unauthorized error message" do
        result = described_class.new(query).execute

        expect(result).to eq({ success: false, error: "Failed after 3 attempts across multiple instances" })
      end
    end

    context "when a persistent network failure or max retries exhaust" do
      before do
        stub_request(:get, %r{degoog_\d:4444/api/extensions\?type=engine})
          .to_return(status: 200, body: { "engines" => [] }.to_json)

        stub_request(:post, %r{degoog_\d:4444/api/search})
          .to_raise(Errno::ECONNREFUSED.new("Connection refused"))
      end

      it "exhausts all retries, marks instances dead, and returns fallback message" do
        result = described_class.new(query).execute

        expect(result).to eq({ success: false, error: "All Degoog instances are currently dead" })
        expect(redis.exists?("degoog:dead:#{instance1}")).to(satisfy { |v| v == true || v.to_i > 0 })
        expect(redis.exists?("degoog:dead:#{instance2}")).to(satisfy { |v| v == true || v.to_i > 0 })
      end
    end

    context "when JSON parsing fails" do
      before do
        stub_request(:get, %r{degoog_\d:4444/api/extensions\?type=engine})
          .to_return(status: 200, body: { "engines" => [] }.to_json)

        stub_request(:post, %r{degoog_\d:4444/api/search})
          .to_return(status: 200, body: "not-json")
      end

      it "exhausts retries and returns max attempts error" do
        result = described_class.new(query).execute

        expect(result).to eq({ error: "Failed after 3 attempts across multiple instances", success: false })
        expect(Rails.logger).to have_received(:error).with(%r{Malformed JSON from http://degoog_}).at_least(:once)
      end
    end
  end
end
