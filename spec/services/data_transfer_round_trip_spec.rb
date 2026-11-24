# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Database data-transfer round trip", type: :service do
  let(:source_user) { create(:user) }
  let(:destination_user) { create(:user) }

  it "exports and restores every registered entity without duplicating records on a second restore" do
    category = create(:category, user: source_user, name: "Engineering")
    target = create(:target, category: category, name: "Example", domain: "example.com")
    pattern = TargetPattern.create!(target: target, path_pattern: "/careers", is_active: false)
    search = create(:search, user: source_user, title: "Ruby roles", query_conditions: "ruby", relevance_mode: "balanced")
    prompt = create(:prompt, search: search, target: target, full_query_text: "site:example.com ruby", status: "failed")
    result = create(
      :result,
      search: search,
      target: target,
      url: "https://example.com/careers/1",
      url_hash: "stable-result-hash",
      status: "watched",
      acknowledged: true,
      verification_status: "verified",
      relevance_score: 87,
      matched_keywords: ["ruby"]
    )

    expect(Database::DataExportService.new(source_user).call).to be(true)
    backup = source_user.data_export.download
    import_path = Rails.root.join("tmp", "round_trip_#{SecureRandom.hex}.json")

    begin
      File.write(import_path, backup)
      expect(Database::DataImportService.new(import_path, user_id: destination_user.id).call).to be(true)

      restored_category = Category.find_by!(user: destination_user, name: category.name)
      restored_target = Target.find_by!(category: restored_category, domain: target.domain)
      restored_search = Search.find_by!(user: destination_user, title: search.title)
      restored_prompt = Prompt.find_by!(search: restored_search, target: restored_target)
      restored_pattern = TargetPattern.find_by!(target: restored_target, path_pattern: pattern.path_pattern)
      restored_result = Result.find_by!(search: restored_search, url_hash: result.url_hash)

      expect(restored_target.name).to eq(target.name)
      expect(restored_pattern.is_active).to be(false)
      expect(restored_prompt.status).to eq("failed")
      expect(restored_result.target_id).to eq(restored_target.id)
      expect(restored_result.status).to eq("watched")
      expect(restored_result.acknowledged).to be(true)
      expect(restored_result.verification_status).to eq("verified")
      expect(restored_result.relevance_score).to eq(87)
      expect(restored_result.matched_keywords).to eq(["ruby"])

      File.write(import_path, backup)
      expect do
        Database::DataImportService.new(import_path, user_id: destination_user.id).call
      end.not_to change { destination_user.reload.categories.count + destination_user.searches.count +
                          restored_category.targets.count + restored_search.prompts.count +
                          restored_search.results.count + TargetPattern.where(target_id: restored_target.id).count }
    ensure
      FileUtils.rm_f(import_path)
    end
  end
end
