# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::Importers::SearchImporter do
  subject(:importer) { described_class.new(records, target_user.id, id_maps) }

  let(:target_user) { create(:user) }
  let(:id_maps) { { searches: {} } }
  let(:timestamp) { "2026-01-01T10:00:00.000Z" }

  describe "#call" do
    let(:records) do
      [
        {
          "id" => "source-search-101",
          "title" => "My Search Query",
          "query_conditions" => "(ruby OR rails)",
          "show_acknowledged" => true,
          "status" => "completed",
          "time_frame" => "week",
          "relevance_mode" => "balanced",
          "created_at" => timestamp,
          "updated_at" => timestamp
        }
      ]
    end

    it "creates a search with the original campaign attributes and updates id maps" do
      expect { importer.call }.to change(Search, :count).by(1)

      search = Search.last
      expect(search.user_id).to eq(target_user.id)
      expect(search.title).to eq("My Search Query")
      expect(search.query_conditions).to eq("(ruby OR rails)")
      expect(search.show_acknowledged).to be(true)
      expect(search.status).to eq("completed")
      expect(search.time_frame).to eq("week")
      expect(search.relevance_mode).to eq("balanced")
      expect(id_maps[:searches]["source-search-101"]).to eq(search.id)
    end

    it "reuses the same campaign when the same backup is imported again" do
      importer.call
      existing_id = id_maps[:searches]["source-search-101"]
      expect { importer.call }.not_to change(Search, :count)
      expect(id_maps[:searches]["source-search-101"]).to eq(existing_id)
    end

    it "keeps distinct campaigns with the same title and query when their creation times differ" do
      second_record = records.first.merge("id" => "source-search-102", "created_at" => "2026-01-01T10:00:01.000Z")
      expect do
        described_class.new(records + [second_record], target_user.id, id_maps).call
      end.to change(Search, :count).by(2)
    end

    context "when optional attributes are missing" do
      let(:records) do
        [{ "id" => "source-search-202", "title" => "Default Search", "query_conditions" => "rails",
           "created_at" => timestamp }]
      end

      it "applies defaults for the search flags and lifecycle fields" do
        importer.call
        search = Search.last

        expect(search.show_acknowledged).to be(false)
        expect(search.status).to eq("pending")
        expect(search.relevance_mode).to eq("strict")
        expect(search.time_frame).to be_nil
      end
    end

    context "when records are empty" do
      let(:records) { [] }

      it "does not create any searches" do
        expect { importer.call }.not_to change(Search, :count)
        expect(id_maps[:searches]).to be_empty
      end
    end
  end
end
