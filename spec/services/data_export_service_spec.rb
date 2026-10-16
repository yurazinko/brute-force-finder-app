# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::DataExportService do
  subject(:service) { described_class.new(user, tables: selected_tables) }

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:selected_tables) { nil }

  let!(:user_category) { create(:category, user: user) }
  let!(:user_target) { create(:target, category: user_category) }
  let!(:user_search) { create(:search, user: user) }
  let!(:user_prompt) { create(:prompt, search: user_search) }
  let!(:user_result) { create(:result, search: user_search) }

  # Foreign records (must be excluded from export)
  let!(:other_category) { create(:category, user: other_user) }
  let!(:other_target) { create(:target, category: other_category) }
  let!(:other_search) { create(:search, user: other_user) }
  let!(:other_prompt) { create(:prompt, search: other_search) }
  let!(:other_result) { create(:result, search: other_search) }

  describe "#call" do
    it "attaches a valid JSON export to the user via Active Storage by default" do
      expect(service.call).to be true
      expect(user.data_export).to be_attached

      exported_data = JSON.parse(user.data_export.download)
      expect(exported_data.keys).to match_array(%w[categories targets searches prompts results])
    end

    it "exports only records belonging to the given user" do
      service.call
      exported_data = JSON.parse(user.data_export.download)

      category_ids = exported_data["categories"].pluck("id")
      target_ids   = exported_data["targets"].pluck("id")
      search_ids   = exported_data["searches"].pluck("id")
      prompt_ids   = exported_data["prompts"].pluck("id")
      result_ids   = exported_data["results"].pluck("id")

      expect(category_ids).to contain_exactly(user_category.id)
      expect(target_ids).to contain_exactly(user_target.id)
      expect(search_ids).to contain_exactly(user_search.id)
      expect(prompt_ids).to contain_exactly(user_prompt.id)
      expect(result_ids).to contain_exactly(user_result.id)

      expect(category_ids).not_to include(other_category.id)
      expect(target_ids).not_to include(other_target.id)
    end

    context "when specific tables are requested" do
      let(:selected_tables) { %w[categories searches] }

      it "exports only the selected tables" do
        service.call
        exported_data = JSON.parse(user.data_export.download)

        expect(exported_data.keys).to match_array(%w[categories searches])
        expect(exported_data).not_to have_key("targets")
        expect(exported_data).not_to have_key("prompts")
        expect(exported_data).not_to have_key("results")
      end

      it "yields progress tracking corresponding to the number of selected tables" do
        yielded_steps = []

        service.call do |progress, message|
          yielded_steps << [progress, message]
        end

        expect(yielded_steps.size).to eq(3) # 2 tables + 1 final completion message
      end
    end

    context "when invalid or unpermitted tables are passed" do
      let(:selected_tables) { %w[categories users non_existent_table] }

      it "filters out unpermitted tables and exports only valid ones" do
        service.call
        exported_data = JSON.parse(user.data_export.download)

        expect(exported_data.keys).to eq(%w[categories])
      end
    end

    context "when a block is given for progress tracking" do
      it "yields progress updates and returns the final HTML download link with signed URL" do
        yielded_steps = []

        service.call do |progress, message|
          yielded_steps << [progress, message]
        end

        expect(yielded_steps.size).to eq(6) # 5 tables + 1 final completion message

        last_progress, last_message = yielded_steps.last
        expect(last_progress).to eq(100)
        expect(last_message).to include("Done! Click <a href=")
        expect(last_message).to include("rails/active_storage")
      end
    end
  end
end
