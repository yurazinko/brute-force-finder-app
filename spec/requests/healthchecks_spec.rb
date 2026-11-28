# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health checks", type: :request do
  it "returns healthy when the database, Redis, and Sidekiq are available" do
    allow(Sidekiq).to receive(:redis).and_yield(double(ping: "PONG"))
    allow(Sidekiq::ProcessSet).to receive(:new).and_return([double])

    get healthz_path

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "status" => "ok",
      "checks" => { "database" => "ok", "redis" => "ok", "sidekiq" => "ok" }
    )
  end

  it "returns 503 when Redis is unavailable" do
    allow(Sidekiq).to receive(:redis).and_raise(Redis::CannotConnectError)

    get healthz_path

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig("checks", "redis")).to eq("failed")
  end
end
