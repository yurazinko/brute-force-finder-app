# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::DataTransferRegistry do
  describe ".resolve_selection" do
    it "returns the single authoritative list when no selection was supplied" do
      expect(described_class.resolve_selection(nil)).to eq(described_class.table_names)
    end

    it "returns no tables for an explicitly empty selection" do
      expect(described_class.resolve_selection([])).to eq([])
    end

    it "includes dependencies and keeps the import/export order" do
      expect(described_class.resolve_selection(%w[target_patterns results])).to eq(
        %w[categories targets target_patterns searches results]
      )
    end

    it "filters unknown and dangerous database tables" do
      expect(described_class.resolve_selection(%w[users active_storage_blobs categories])).to eq(%w[categories])
    end
  end
end
