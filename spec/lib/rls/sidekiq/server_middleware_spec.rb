# frozen_string_literal: true

require "rails_helper"
require "rls/sidekiq_support/server_middleware"

class DummyRlsWorker
  include Rls::SidekiqSupport

  def perform(user_id, account_id); end
end

class DummyNonRlsWorker
  def perform(user_id); end
end

RSpec.describe Rls::SidekiqSupport::ServerMiddleware do
  subject(:middleware) { described_class.new }

  it "uses only the explicit rls_user_id payload field" do
    worker = DummyRlsWorker.new
    expect(middleware).to receive(:with_rls_user).with(42).and_yield
    middleware.call(worker, { "args" => [42, 7], "rls_user_id" => 42 }, "default") { true }
  end

  it "fails closed when an RLS-scoped job has no tenant metadata" do
    worker = DummyRlsWorker.new
    expect { middleware.call(worker, { "args" => [42, 7] }, "default") { true } }
      .to raise_error(described_class::MissingTenantContextError, /rls_user_id/)
  end

  it "recognizes an RLS worker wrapped by ActiveJob" do
    job = {
      "wrapped" => "DummyRlsWorker",
      "rls_user_id" => 42,
      "args" => [{ "arguments" => [42, 7] }]
    }
    expect(middleware).to receive(:with_rls_user).with(42).and_yield

    expect(middleware.call(Object.new, job, "default") { :ok }).to eq(:ok)
  end

  it "does not add RLS requirements to non-tenant jobs" do
    expect(middleware.call(DummyNonRlsWorker.new, { "args" => [42] }, "default") { :ok }).to eq(:ok)
  end
end
