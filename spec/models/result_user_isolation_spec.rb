# frozen_string_literal: true

require "rails_helper"
require "rls/context"

RSpec.describe "Result tenant ownership", type: :model do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:search) { create(:search, user: user) }
  let(:rls_context) do
    Class.new do
      include Rls::Context
    end.new
  end

  it "derives user_id from the owning search on insert" do
    result = build(:result, search: search)

    rls_context.with_rls_user(user.id) { result.save! }

    expect(result.reload.user_id).to eq(user.id)
  end

  it "rejects a caller-supplied tenant that differs from the search owner" do
    result = build(:result, search: search, user_id: other_user.id)

    expect do
      rls_context.with_rls_user(user.id) { result.save! }
    end.to raise_error(ActiveRecord::StatementInvalid, /Result tenant does not match search tenant/)
  end

  it "uses a direct tenant equality policy rather than an EXISTS subquery" do
    policy = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
      SELECT pg_catalog.pg_get_expr(polqual, polrelid)
        FROM pg_catalog.pg_policy
       WHERE polname = 'result_user_isolation'
         AND polrelid = 'public.results'::regclass
    SQL

    expect(policy).to include("user_id")
    expect(policy).not_to include("EXISTS")
  end
end
