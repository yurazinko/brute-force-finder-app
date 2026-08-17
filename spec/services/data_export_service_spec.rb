# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::DataExportService do
  subject(:service) { described_class.new(user, custom_path) }

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  let(:custom_path) { Rails.root.join("tmp", "test-export-#{user.id}.json") }

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

  after do
    FileUtils.rm_f(custom_path)
  end

  describe "#call" do
    it "creates a valid JSON file with exported data" do
      expect(service.call).to be true
      expect(File.exist?(custom_path)).to be true

      exported_data = JSON.parse(File.read(custom_path))

      expect(exported_data.keys).to match_array(%w[categories targets searches prompts results])
    end

    it "exports only records belonging to the given user" do
      service.call
      exported_data = JSON.parse(File.read(custom_path))

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

    context "when a block is given for progress tracking" do
      it "yields progress updates and returns the final HTML download link" do
        yielded_steps = []

        service.call do |progress, message|
          yielded_steps << [progress, message]
        end

        expect(yielded_steps.size).to eq(6) # 5 tables + 1 final completion message

        last_progress, last_message = yielded_steps.last
        expect(last_progress).to eq(100)
        expect(last_message).to include("Done! Click <a href='/#{custom_path.basename}' download")
      end
    end

    context "when output_path is not provided" do
      subject(:service_with_default_path) { described_class.new(user) }

      after do
        FileUtils.rm_f(service_with_default_path.output_path)
      end

      it "uses the default path in public directory" do
        expect(service_with_default_path.output_path.to_s).to include("public/export-user-#{user.id}-")

        service_with_default_path.call
        expect(File.exist?(service_with_default_path.output_path)).to be true
      end
    end
  end
end
