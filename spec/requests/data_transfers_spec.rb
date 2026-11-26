# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe "DataTransfers", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }

  before do
    sign_in user
    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all
  end

  describe "GET /data_transfers" do
    it "renders export options from the shared data-transfer registry" do
      get data_transfers_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Database Sync & Backups")
      expect(response.body).to include("Export Database Backup")
      expect(response.body).to include("Import & Upsert Sync")
      Database::DataTransferRegistry.table_names.each do |table_name|
        expect(response.body).to include("value=\"#{table_name}\"")
      end
    end
  end

  describe "POST /data_transfers/export" do
    let(:selected_tables) { %w[categories targets] }

    context "when Turbo Stream request" do
      it "enqueues DataExportJob and renders the progress partial" do
        expect do
          post export_data_transfers_path,
               params: { tables: selected_tables + [""] },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end.to change(DataExportJob.jobs, :size).by(1)

        expect(DataExportJob.jobs.last["args"]).to eq([user.id, selected_tables])
        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include('<turbo-stream action="replace" target="export">')
        expect(response.body).to include("Starting export job...")
      end

      it "preserves an explicitly empty table selection" do
        post export_data_transfers_path,
             params: { tables: [""] },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(DataExportJob.jobs.last["args"]).to eq([user.id, []])
      end
    end

    context "when HTML request" do
      it "enqueues DataExportJob and redirects back to data_transfers_path" do
        post export_data_transfers_path, params: { tables: selected_tables }

        expect(DataExportJob.jobs.last["args"]).to eq([user.id, selected_tables])
        expect(response).to redirect_to(data_transfers_path)
      end
    end
  end

  describe "POST /data_transfers/import" do
    let(:json_content) { { categories: [{ name: "Test Category" }] }.to_json }
    let(:file) do
      Rack::Test::UploadedFile.new(
        StringIO.new(json_content),
        "application/json",
        original_filename: "backup.json"
      )
    end

    it "writes the upload to tmp, enqueues DataImportJob, and renders turbo-stream progress" do
      post import_data_transfers_path,
           params: { file: file },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      job = DataImportJob.jobs.last
      expect(job["args"].second).to eq(user.id)
      expect(File.read(job["args"].first)).to eq(json_content)
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("File uploaded. Starting sync...")
      FileUtils.rm_f(job["args"].first)
    end

    it "does not enqueue an import job when no file is uploaded" do
      expect do
        post import_data_transfers_path, params: { file: nil }
      end.not_to change(DataImportJob.jobs, :size)

      expect(response).to redirect_to(data_transfers_path)
      expect(flash[:alert]).to eq("Please upload a valid JSON file.")
    end
  end

  context "when user is not authenticated" do
    before { sign_out user }

    it "requires authentication for data transfer endpoints" do
      get data_transfers_path
      expect(response).to have_http_status(:redirect)

      post export_data_transfers_path
      expect(response).to have_http_status(:redirect)

      post import_data_transfers_path
      expect(response).to have_http_status(:redirect)
    end
  end
end
