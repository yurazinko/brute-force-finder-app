# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rls::Context do
  let(:context_class) do
    Class.new do
      include Rls::Context
    end
  end

  it "sets the tenant only for the transaction and restores the previous value" do
    connection = ActiveRecord::Base.connection
    previous_value = connection.select_value("SELECT current_setting('app.current_user_id', true)").to_s

    context_class.with_rls_user(42) do
      expect(connection.select_value("SELECT current_user_id()").to_i).to eq(42)
      expect(context_class.current_rls_user_id.to_i).to eq(42)
    end

    expect(connection.select_value("SELECT current_setting('app.current_user_id', true)").to_s).to eq(previous_value)
    expect(context_class.current_rls_user_id).to be_nil
  end

  it "restores the parent tenant after a nested context" do
    connection = ActiveRecord::Base.connection

    context_class.with_rls_user(10) do
      expect(connection.select_value("SELECT current_user_id()").to_i).to eq(10)

      context_class.with_rls_user(42) do
        expect(connection.select_value("SELECT current_user_id()").to_i).to eq(42)
      end

      expect(connection.select_value("SELECT current_user_id()").to_i).to eq(10)
      expect(context_class.current_rls_user_id.to_i).to eq(10)
    end

    expect(context_class.current_rls_user_id).to be_nil
  end

  it "restores the previous value even when the block raises" do
    connection = ActiveRecord::Base.connection

    expect do
      context_class.with_rls_user(42) do
        expect(connection.select_value("SELECT current_user_id()").to_i).to eq(42)
        raise "boom"
      end
    end.to raise_error("boom")

    expect(connection.select_value("SELECT NULLIF(current_setting('app.current_user_id', true), '')")).to be_nil
    expect(context_class.current_rls_user_id).to be_nil
  end

  it "discards a connection with an untracked tenant setting inside an open transaction" do
    connection = ActiveRecord::Base.connection
    pool = ActiveRecord::Base.connection_pool
    allow(connection).to receive(:transaction_open?).and_return(true)
    allow(connection).to receive(:select_value)
      .with("SELECT NULLIF(current_setting('app.current_user_id', true), '')").and_return("99")
    expect(pool).to receive(:remove).with(connection)

    expect { context_class.with_rls_user(42) }
      .to raise_error(Rls::Context::StaleTenantContextError)
  end

  it "rejects missing and non-positive tenants" do
    [nil, "", "0", "-1", "not-an-id"].each do |invalid_id|
      expect { context_class.with_rls_user(invalid_id) }.to raise_error(ArgumentError)
    end
  end
end
