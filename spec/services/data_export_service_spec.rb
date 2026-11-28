# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::DataExportService do
  subject(:service) { described_class.new(user, tables: selected_tables) }

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:selected_tables) { nil }

  let!(:user_category) { create(:category, user: user) }
  let!(:user_target) { create(:target, category: user_category) }
  let!(:user_pattern) do
    TargetPattern.create!(target: user_target, path_pattern: "/jobs", is_active: false)
  end
  let!(:user_search) { create(:search, user: user) }
  let!(:user_prompt) { create(:prompt, search: user_search, target: user_target) }
  let!(:user_result) { create(:result, search: user_search, target: user_target) }

  let!(:other_category) { create(:category, user: other_user) }
  let!(:other_target) { create(:target, category: other_category) }
  let!(:other_pattern) { TargetPattern.create!(target: other_target, path_pattern: "/private") }
  let!(:other_search) { create(:search, user: other_user) }
  let!(:other_prompt) { create(:prompt, search: other_search, target: other_target) }
  let!(:other_result) { create(:result, search: other_search, target: other_target) }

  def read_exported_data
    export_lines = user.data_export.download.each_line.reject { |line| line.strip.empty? }
    parse_export_lines(export_lines)
  end

  def parse_export_lines(lines)
    header = JSON.parse(lines.shift)
    return {} if header.fetch("tables").empty?

    tables = header.fetch("tables").index_with { [] }
    lines.each { |line| append_export_record(tables, line) }
    tables
  end

  def append_export_record(tables, line)
    payload = JSON.parse(line)
    tables.fetch(payload.fetch("table")) << payload.fetch("record")
  end

  describe "#call" do
    it "exports every registered table, including target patterns" do
      expect(service.call).to be(true)
      expect(user.data_export).to be_attached

      exported_data = read_exported_data
      expect(exported_data.keys).to match_array(Database::DataTransferRegistry.table_names)
      expect(exported_data.fetch("target_patterns").pluck("id")).to contain_exactly(user_pattern.id)
    end

    it "writes a versioned NDJSON stream rather than materializing a JSON object" do
      service.call
      lines = user.data_export.download.lines

      header = JSON.parse(lines.first)
      expect(header).to include(
        "_format" => Database::DataExportService::FORMAT,
        "version" => Database::DataExportService::FORMAT_VERSION,
        "tables" => Database::DataTransferRegistry.table_names
      )
      expect(lines.drop(1).all? { |line| JSON.parse(line).keys.sort == %w[record table] }).to be(true)
      expect(user.data_export.blob.content_type).to eq("application/x-ndjson")
    end

    it "preserves all data fields serialized by Active Record" do
      user_search.update!(relevance_mode: "balanced")
      user_result.update!(verification_status: "verified", target_id: user_target.id)

      service.call
      exported_data = read_exported_data

      expect(exported_data.fetch("searches").first.fetch("relevance_mode")).to eq("balanced")
      expect(exported_data.fetch("results").first.fetch("verification_status")).to eq("verified")
    end

    it "exports only records owned by the given user, including nested target patterns" do
      service.call
      exported_data = read_exported_data

      expected_ids = {
        "categories" => [user_category.id],
        "targets" => [user_target.id],
        "target_patterns" => [user_pattern.id],
        "searches" => [user_search.id],
        "prompts" => [user_prompt.id],
        "results" => [user_result.id]
      }

      expected_ids.each do |table, ids|
        expect(exported_data.fetch(table).pluck("id")).to match_array(ids)
      end

      expect(exported_data.fetch("target_patterns").pluck("id")).not_to include(other_pattern.id)
      expect(exported_data.fetch("results").pluck("id")).not_to include(other_result.id)
    end

    context "when specific tables are requested" do
      let(:selected_tables) { %w[categories searches] }

      it "exports only the requested tables when no dependencies are needed" do
        service.call
        exported_data = read_exported_data

        expect(exported_data.keys).to match_array(%w[categories searches])
      end

      it "tracks progress for the selected table count and completion" do
        yielded_steps = []
        service.call { |progress, message| yielded_steps << [progress, message] }

        expect(yielded_steps.size).to eq(3)
        expect(yielded_steps.last.first).to eq(100)
      end
    end

    context "when a child table is selected" do
      let(:selected_tables) { %w[target_patterns] }

      it "automatically includes the required parent tables" do
        service.call
        exported_data = read_exported_data

        expect(exported_data.keys).to eq(%w[categories targets target_patterns])
      end
    end

    context "when an empty table list is explicitly requested" do
      let(:selected_tables) { [] }

      it "exports an empty table declaration rather than silently exporting the whole database" do
        service.call
        expect(read_exported_data).to eq({})
      end
    end

    context "when a relation contains more rows than one fetch batch" do
      let(:selected_tables) { %w[results] }

      before do
        stub_const("Database::DataExportService::BATCH_SIZE", 1)
        create_list(:result, 3, search: user_search)
      end

      it "exports every database row rather than a hardcoded sample or first batch" do
        service.call
        exported_data = read_exported_data

        expect(exported_data.fetch("results").size).to eq(4)
      end
    end

    context "when invalid or unpermitted tables are passed" do
      let(:selected_tables) { %w[categories users non_existent_table] }

      it "filters out unpermitted tables" do
        service.call
        exported_data = read_exported_data
        expect(exported_data.keys).to eq(%w[categories])
      end
    end

    it "reports progress for every registered table and a final completion message" do
      yielded_steps = []
      service.call { |progress, message| yielded_steps << [progress, message] }

      expect(yielded_steps.size).to eq(Database::DataTransferRegistry.table_names.size + 1)
      expect(yielded_steps.last.first).to eq(100)
      expect(yielded_steps.last.last).to include("Done! Click <a href=")
      expect(yielded_steps.last.last).to include("data_transfers/download")
    end
  end
end
