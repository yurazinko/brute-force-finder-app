# frozen_string_literal: true

require "rails_helper"
require "rls/sidekiq/server_middleware" # Примусове завантаження для SimpleCov

class DummyRlsWorker
  include Rls::Sidekiq if defined?(Rls::Sidekiq)

  def perform(user_id, account_id); end
end

class DummyNamedParamWorker
  include Rls::Sidekiq if defined?(Rls::Sidekiq)

  def perform(target_id, current_user_id, options = {}); end
end

class DummyUnknownParamWorker
  include Rls::Sidekiq if defined?(Rls::Sidekiq)

  def perform(foo, bar); end
end

class DummyNonRlsWorker
  def perform(user_id); end
end

RSpec.describe Rls::Sidekiq::ServerMiddleware do
  subject(:middleware) { described_class.new }

  let(:queue) { "default" }

  describe "#call" do
    context "when worker is NOT an instance of Rls::Sidekiq" do
      let(:worker) { DummyNonRlsWorker.new }

      it "yields without wrapping in with_rls_user" do
        expect(middleware).not_to receive(:with_rls_user)

        executed = false
        middleware.call(worker, { "args" => [123] }, queue) do
          executed = true
        end

        expect(executed).to be true
      end
    end

    context "when worker IS an instance of Rls::Sidekiq" do
      before do
        DummyRlsWorker.include(Rls::Sidekiq)
        DummyNamedParamWorker.include(Rls::Sidekiq)
        DummyUnknownParamWorker.include(Rls::Sidekiq)
      end

      context "and user_id is extracted from a Hash parameter" do
        let(:worker) { DummyRlsWorker.new }

        it "extracts user_id from symbol key :user_id" do
          job = { "args" => [{ "user_id" => 42, "other" => "value" }] }

          expect(middleware).to receive(:with_rls_user).with(42).and_yield

          middleware.call(worker, job, queue) { true }
        end

        it "extracts user_id from string key :_user_id" do
          job = { "args" => [{ "_user_id" => "99" }] }

          expect(middleware).to receive(:with_rls_user).with("99").and_yield

          middleware.call(worker, job, queue) { true }
        end
      end

      context "and user_id is extracted by parameter name ending with 'user_id'" do
        let(:worker) { DummyNamedParamWorker.new }

        it "finds argument matching the parameter name `current_user_id`" do
          job = { "args" => [100, 555, { "foo" => "bar" }] }

          expect(middleware).to receive(:with_rls_user).with(555).and_yield

          middleware.call(worker, job, queue) { true }
        end
      end

      context "and user_id is extracted as a single numeric argument" do
        let(:worker) { DummyRlsWorker.new }

        it "extracts user_id when args has exactly one integer-like string or number" do
          job = { "args" => [777] }

          expect(middleware).to receive(:with_rls_user).with(777).and_yield

          middleware.call(worker, job, queue) { true }
        end
      end

      context "when no user_id can be extracted" do
        let(:worker) { DummyUnknownParamWorker.new }

        it "calls with_rls_user with nil" do
          job = { "args" => %w[not_a_number some_string] }

          expect(middleware).to receive(:with_rls_user).with(nil).and_yield

          middleware.call(worker, job, queue) { true }
        end
      end

      context "integration with Rls::Context (DB context setting)" do
        let(:worker) { DummyRlsWorker.new }
        let(:job) { { "args" => [123] } }

        it "executes the block inside SQL transaction setting RLS user_id" do
          expect(ActiveRecord::Base.connection).to receive(:execute)
            .with("SET LOCAL app.current_user_id = '123'")
            .and_call_original

          yielded = false
          middleware.call(worker, job, queue) do
            yielded = true
          end

          expect(yielded).to be true
        end
      end
    end
  end
end
