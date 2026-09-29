# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::Importers::SearchImporter do
  subject(:importer) { described_class.new(records, target_user.id, id_maps) }

  let(:target_user) { create(:user) }
  let(:id_maps) { { "searches" => {} } }

  describe "#call" do
    context "when importing valid records with full attributes" do
      let(:records) do
        [
          {
            "id" => "old-id-101",
            "title" => "My Search Query",
            "query_conditions" => { "keyword" => "ruby" },
            "show_acknowledged" => true,
            "status" => "completed",
            "time_frame" => "week",
            "created_at" => "2026-01-01T10:00:00Z",
            "updated_at" => "2026-01-02T10:00:00Z"
          }
        ]
      end

      it "creates a Search record with provided attributes and updates id_maps" do
        expect { importer.call }.to change(Search, :count).by(1)

        created_search = Search.last
        expect(created_search.user_id).to eq(target_user.id)
        expect(created_search.title).to eq("My Search Query")

        if created_search.query_conditions.is_a?(String)
          expect(created_search.query_conditions).to include("keyword")
          expect(created_search.query_conditions).to include("ruby")
        else
          expect(created_search.query_conditions).to eq({ "keyword" => "ruby" })
        end

        expect(created_search.show_acknowledged).to be true
        expect(created_search.status).to eq("completed")
        expect(created_search.time_frame).to eq("week")

        expect(id_maps["searches"]["old-id-101"]).to eq(created_search.id)
      end
    end

    context "when optional attributes are missing (testing fallback default values)" do
      let(:records) do
        [
          {
            "id" => "old-id-202",
            "title" => "Default Search",
            "query_conditions" => { "keyword" => "rails" },
            "time_frame" => nil,
            "created_at" => "2026-02-01T10:00:00Z",
            "updated_at" => "2026-02-01T10:00:00Z"
          }
        ]
      end

      it "applies default fallback values for show_acknowledged and status" do
        importer.call

        created_search = Search.last
        expect(created_search.show_acknowledged).to be false
        expect(created_search.status).to eq("pending")
        expect(created_search.time_frame).to be_nil
        expect(id_maps["searches"]["old-id-202"]).to eq(created_search.id)
      end
    end

    context "when records array is empty" do
      let(:records) { [] }

      it "does not create any Search records" do
        expect { importer.call }.not_to change(Search, :count)
        expect(id_maps["searches"]).to be_empty
      end
    end
  end
end
