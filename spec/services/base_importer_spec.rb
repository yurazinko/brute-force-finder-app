# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::Importers::BaseImporter do
  subject(:importer) { described_class.new(records, target_user_id, id_maps) }

  let(:records) { [{ "id" => 1 }] }
  let(:target_user_id) { 42 }
  let(:id_maps) { { "searches" => {} } }

  describe "#initialize" do
    it "correctly assigns attr_readers" do
      expect(importer.records).to eq(records)
      expect(importer.target_user_id).to eq(target_user_id)
      expect(importer.id_maps).to eq(id_maps)
    end
  end

  describe "#call" do
    it "raises NotImplementedError" do
      expect { importer.call }.to raise_error(
        NotImplementedError,
        "Database::Importers::BaseImporter must implement #call"
      )
    end
  end
end
