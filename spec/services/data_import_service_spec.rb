# frozen_string_literal: true

require "rails_helper"

RSpec.describe Database::DataImportService, type: :service do
  let(:user) { create(:user) }
  let(:temp_file_path) { Rails.root.join("tmp", "test_import_#{SecureRandom.hex}.json") }
  let(:timestamp) { "2026-06-15T10:00:00.000Z" }

  let(:valid_json_data) do
    {
      "categories" => [
        { "id" => 1, "name" => "Tech", "created_at" => timestamp, "updated_at" => timestamp }
      ],
      "targets" => [
        {
          "id" => 2, "category_id" => 1, "domain" => "example.com", "name" => "Example",
          "is_active" => true, "allow_query_strings" => false, "created_at" => timestamp, "updated_at" => timestamp
        }
      ],
      "target_patterns" => [
        { "id" => 3, "target_id" => 2, "path_pattern" => "/jobs", "is_active" => false,
          "created_at" => timestamp, "updated_at" => timestamp }
      ],
      "searches" => [
        { "id" => 4, "title" => "Ruby Search", "query_conditions" => "ruby", "status" => "completed",
          "show_acknowledged" => false, "time_frame" => "week", "relevance_mode" => "balanced",
          "created_at" => timestamp, "updated_at" => timestamp }
      ],
      "prompts" => [
        { "id" => 5, "search_id" => 4, "target_id" => 2, "full_query_text" => "site:example.com ruby",
          "status" => "failed", "error_message" => "429", "created_at" => timestamp, "updated_at" => timestamp }
      ],
      "results" => [
        { "id" => 6, "search_id" => 4, "target_id" => 2, "title" => "Ruby job",
          "url" => "https://example.com/jobs/1", "url_hash" => "result-hash", "status" => "watched",
          "acknowledged" => true, "verification_status" => "verified", "relevance_score" => 91,
          "matched_keywords" => ["ruby"], "created_at" => timestamp, "updated_at" => timestamp }
      ]
    }
  end

  before do
    File.write(temp_file_path, JSON.generate(valid_json_data))
  end

  after do
    FileUtils.rm_f(temp_file_path)
  end

  describe "#call" do
    it "returns false when the file does not exist" do
      service = described_class.new("non_existent_file.json", user_id: user.id)
      expect(service.call).to be(false)
    end

    it "imports the full dependency graph and preserves data attributes" do
      expect do
        described_class.new(temp_file_path, user_id: user.id).call
      end.to change(Category, :count).by(1)
       .and change(Target, :count).by(1)
       .and change(TargetPattern, :count).by(1)
       .and change(Search, :count).by(1)
       .and change(Prompt, :count).by(1)
       .and change(Result, :count).by(1)

      category = Category.find_by!(user_id: user.id, name: "Tech")
      target = Target.find_by!(category: category, domain: "example.com")
      search = Search.find_by!(user_id: user.id, title: "Ruby Search")
      pattern = TargetPattern.find_by!(target: target, path_pattern: "/jobs")
      prompt = Prompt.find_by!(search: search, target: target)
      result = Result.find_by!(search: search, url_hash: "result-hash")

      expect(pattern.is_active).to be(false)
      expect(prompt.status).to eq("failed")
      expect(prompt.error_message).to eq("429")
      expect(result.target_id).to eq(target.id)
      expect(result.status).to eq("watched")
      expect(result.acknowledged).to be(true)
      expect(result.verification_status).to eq("verified")
      expect(result.relevance_score).to eq(91)
      expect(result.matched_keywords).to eq(["ruby"])
    end

    it "is idempotent when the same backup is imported more than once" do
      importer = -> { described_class.new(temp_file_path, user_id: user.id).call }
      importer.call
      counts_after_first_import = [Category, Target, TargetPattern, Search, Prompt, Result].map(&:count)

      File.write(temp_file_path, JSON.generate(valid_json_data))
      importer.call

      expect([Category, Target, TargetPattern, Search, Prompt, Result].map(&:count)).to eq(counts_after_first_import)
    end

    it "maps equal domains independently within different categories" do
      second_category_id = 11
      second_target_id = 12
      data = valid_json_data.deep_dup
      data["categories"] << { "id" => second_category_id, "name" => "Other", "created_at" => timestamp,
                              "updated_at" => timestamp }
      data["targets"] << { "id" => second_target_id, "category_id" => second_category_id,
                           "domain" => "example.com", "name" => "Other Example", "created_at" => timestamp,
                           "updated_at" => timestamp }
      File.write(temp_file_path, JSON.generate(data))

      described_class.new(temp_file_path, user_id: user.id).call

      targets = Target.joins(:category).where(categories: { user_id: user.id }, domain: "example.com")
      expect(targets.count).to eq(2)
      expect(targets.map(&:name)).to contain_exactly("Example", "Other Example")
    end

    it "rolls back the entire import and keeps the file when a dependency is missing" do
      broken_data = valid_json_data.except("categories")
      File.write(temp_file_path, JSON.generate(broken_data))

      expect do
        described_class.new(temp_file_path, user_id: user.id).call
      end.to raise_error(ArgumentError, /category that was not imported/)

      expect(Category.where(user_id: user.id)).to be_empty
      expect(Target.joins(:category).where(categories: { user_id: user.id })).to be_empty
      expect(File.exist?(temp_file_path)).to be(true)
    end

    it "rejects malformed table payloads instead of silently importing partial data" do
      File.write(temp_file_path, JSON.generate("categories" => { "id" => 1, "name" => "Tech" }))

      expect do
        described_class.new(temp_file_path, user_id: user.id).call
      end.to raise_error(ArgumentError, /must contain an array of objects/)
      expect(Category.where(user_id: user.id)).to be_empty
    end

    it "tracks progress and deletes the file after successful import" do
      yielded_progress = []
      described_class.new(temp_file_path, user_id: user.id).call do |progress, message|
        yielded_progress << [progress, message]
      end

      expect(yielded_progress.first.last).to eq("Importing categories...")
      expect(yielded_progress.last).to eq([100, "Import completed successfully!"])
      expect(File.exist?(temp_file_path)).to be(false)
    end
  end
end
