# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::Importers::PromptImporter do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user) }
  let(:target) { create(:target, category: create(:category, user: user)) }
  let(:id_maps) do
    { searches: { "source-search" => search.id }, targets: { "source-target" => target.id } }
  end
  let(:records) do
    [
      { "search_id" => "source-search", "target_id" => "source-target",
        "full_query_text" => "site:example.com ruby", "status" => "failed", "error_message" => "429" },
      { "search_id" => "source-search", "target_id" => "source-target",
        "full_query_text" => "site:example.com ruby", "status" => "success", "error_message" => nil }
    ]
  end

  it "deduplicates duplicate prompt identities and applies the last state" do
    expect do
      described_class.new(records, user.id, id_maps).call
    end.to change(search.prompts, :count).by(1)

    prompt = search.prompts.find_by!(target: target, full_query_text: "site:example.com ruby")
    expect(prompt.status).to eq("success")
    expect(prompt.error_message).to be_nil
  end

  it "preserves both backup timestamps when inserting a new prompt" do
    imported_created_at = Time.zone.parse("2023-02-03 04:05:06")
    imported_updated_at = Time.zone.parse("2024-05-06 07:08:09")
    import_records = [
      {
        "search_id" => "source-search",
        "target_id" => "source-target",
        "full_query_text" => "site:example.com new query",
        "status" => "pending",
        "created_at" => imported_created_at.iso8601,
        "updated_at" => imported_updated_at.iso8601
      }
    ]

    described_class.new(import_records, user.id, id_maps).call

    prompt = search.prompts.find_by!(target: target, full_query_text: "site:example.com new query")
    expect(prompt.created_at).to eq(imported_created_at)
    expect(prompt.updated_at).to eq(imported_updated_at)
  end

  it "preserves the imported updated_at when updating an existing prompt" do
    query = "site:example.com ruby"
    prompt = Prompt.create!(
      search: search,
      target: target,
      full_query_text: query,
      status: "failed",
      error_message: "previous error"
    )

    original_created_at = Time.zone.parse("2022-01-02 03:04:05")
    prompt.update_columns(created_at: original_created_at)

    imported_updated_at = Time.zone.parse("2025-06-07 08:09:10")
    import_records = [
      {
        "search_id" => "source-search",
        "target_id" => "source-target",
        "full_query_text" => query,
        "status" => "success",
        "error_message" => nil,
        "created_at" => Time.zone.parse("2024-02-03 04:05:06").iso8601,
        "updated_at" => imported_updated_at.iso8601
      }
    ]

    described_class.new(import_records, user.id, id_maps).call

    prompt.reload
    expect(prompt.status).to eq("success")
    expect(prompt.error_message).to be_nil
    # A merge updates mutable prompt state but keeps the destination record's
    # original creation timestamp.
    expect(prompt.created_at).to eq(original_created_at)
    expect(prompt.updated_at).to eq(imported_updated_at)
  end

  it "uses the global partial unique index for prompts without a target" do
    global_rows = [{ "search_id" => "source-search", "full_query_text" => "ruby", "status" => "pending" }]
    expect do
      described_class.new(global_rows, user.id, id_maps).call
    end.to change(search.prompts, :count).by(1)

    expect do
      described_class.new(global_rows, user.id, id_maps).call
    end.not_to change(search.prompts, :count)
  end
end
