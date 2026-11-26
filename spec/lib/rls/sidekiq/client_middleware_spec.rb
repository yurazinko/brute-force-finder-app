# frozen_string_literal: true

require "rails_helper"
require "rls/sidekiq_support/client_middleware"

class DummyClientRlsWorker
  include Rls::SidekiqSupport

  def perform(search_id, _user_id); end
end

class DummyClientUnknownRlsWorker
  include Rls::SidekiqSupport

  def perform(search_id); end
end

RSpec.describe Rls::SidekiqSupport::ClientMiddleware do
  subject(:middleware) { described_class.new }

  it "maps SearchActivationJob-style _user_id by declared argument name" do
    job = { "class" => "DummyClientRlsWorker", "args" => [88, 42] }
    middleware.call(DummyClientRlsWorker, job, "default") { true }
    expect(job["rls_user_id"]).to eq(42)
  end

  it "inherits the active database tenant for chained jobs with no tenant argument" do
    job = { "class" => "DummyClientUnknownRlsWorker", "args" => [88] }
    allow(ActiveRecord::Base.connection).to receive(:select_value)
      .with("SELECT current_user_id()").and_return(42)

    middleware.call(DummyClientUnknownRlsWorker, job, "default") { true }

    expect(job["rls_user_id"]).to eq(42)
  end

  it "extracts a tenant from ActiveJob arguments wrapped by Sidekiq" do
    job = {
      "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
      "wrapped" => "DummyClientRlsWorker",
      "args" => [{ "job_class" => "DummyClientRlsWorker", "arguments" => [88, 42] }]
    }

    middleware.call("ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper", job, "default") { true }

    expect(job["rls_user_id"]).to eq(42)
  end

  it "rejects an RLS job when neither arguments nor the active database context has a tenant" do
    job = { "class" => "DummyClientUnknownRlsWorker", "args" => [88] }
    allow(ActiveRecord::Base.connection).to receive(:select_value)
      .with("SELECT current_user_id()").and_return(nil)

    expect { middleware.call(DummyClientUnknownRlsWorker, job, "default") { true } }
      .to raise_error(described_class::MissingTenantContextError)
  end
end
