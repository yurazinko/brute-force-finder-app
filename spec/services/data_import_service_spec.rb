# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataImportService, type: :service do
  let(:temp_file_path) { Rails.root.join("tmp", "test_import_#{SecureRandom.hex}.json") }

  let(:valid_json_data) do
    {
      "categories" => [
        { "id" => 1, "name" => "Tech", "created_at" => "2026-06-15T10:00:00Z", "updated_at" => "2026-06-15T10:00:00Z" }
      ],
      "targets" => [
        { "id" => 1, "category_id" => 1, "domain" => "example.com", "name" => "Example", "is_active" => true, "created_at" => "2026-06-15T10:00:00Z", "updated_at" => "2026-06-15T10:00:00Z" }
      ],
      "searches" => [],
      "prompts" => [],
      "results" => []
    }
  end

  after do
    FileUtils.rm_f(temp_file_path)
  end

  describe "#call" do
    context "when file does not exist" do
      it "returns false" do
        service = described_with_file_path("non_existent_file.json")
        expect(service.call).to be false
      end
    end

    context "when file exists" do
      before do
        File.write(temp_file_path, JSON.generate(valid_json_data))
      end

      it "imports data into the database" do
        expect {
          described_class.new(temp_file_path).call
        }.to change(Category, :count).by(1)
         .and change(Target, :count).by(1)

        category = Category.find(1)
        expect(category.name).to eq("Tech")
      end

      it "performs an upsert if the record already exists" do
        Category.create!(id: 1, name: "Old Name")

        expect {
          described_class.new(temp_file_path).call
        }.not_to change(Category, :count)

        expect(Category.find(1).name).to eq("Tech")
      end

      it "tracks progress via block execution" do
        yielded_progress = []

        described_class.new(temp_file_path).call do |progress, message|
          yielded_progress << { progress: progress, message: message }
        end

        expect(yielded_progress.first[:message]).to eq("Importing categories...")
        expect(yielded_progress.last[:progress]).to eq(100)
        expect(yielded_progress.last[:message]).to eq("Import completed successfully!")
      end

      it "deletes the file after processing" do
        expect(File.exist?(temp_file_path)).to be true
        described_class.new(temp_file_path).call
        expect(File.exist?(temp_file_path)).to be false
      end
    end
  end

  def described_with_file_path(path)
    described_class.new(path)
  end
end
