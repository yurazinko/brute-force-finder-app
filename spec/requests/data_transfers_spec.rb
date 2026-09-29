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
    it "renders the index page successfully" do
      get data_transfers_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Database Sync & Backups")
      expect(response.body).to include("Export Database to JSON")
      expect(response.body).to include("Import & Upsert Sync")
    end
  end

  describe "POST /data_transfers/export" do
    let(:selected_tables) { %w[categories targets] }

    context "when Turbo Stream request" do
      it "enqueues DataExportJob and renders turbo stream progress partial" do
        expect do
          post export_data_transfers_path, params: { tables: selected_tables + [""] }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end.to change(DataExportJob.jobs, :size).by(1)

        enqueued_job = DataExportJob.jobs.last
        expect(enqueued_job["args"]).to eq([user.id, selected_tables])

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include('<turbo-stream action="replace" target="export">')
        expect(response.body).to include("Starting export job...")
      end

      it "handles export with empty table parameters correctly" do
        expect do
          post export_data_transfers_path, params: { tables: [""] }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end.to change(DataExportJob.jobs, :size).by(1)

        enqueued_job = DataExportJob.jobs.last
        expect(enqueued_job["args"]).to eq([user.id, []])

        expect(response).to have_http_status(:success)
      end
    end

    context "when HTML request" do
      it "enqueues DataExportJob and redirects back to data_transfers_path" do
        expect do
          post export_data_transfers_path, params: { tables: selected_tables }
        end.to change(DataExportJob.jobs, :size).by(1)

        enqueued_job = DataExportJob.jobs.last
        expect(enqueued_job["args"]).to eq([user.id, selected_tables])

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

    context "when valid file is uploaded" do
      context "with Turbo Stream request" do
        it "writes file to tmp, enqueues DataImportJob, and renders turbo stream" do
          expect do
            post import_data_transfers_path, params: { file: file }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
          end.to change(DataImportJob.jobs, :size).by(1)

          enqueued_job = DataImportJob.jobs.last
          expect(enqueued_job["args"].first).to be_a(String)
          expect(enqueued_job["args"].second).to eq(user.id)

          expect(response).to have_http_status(:success)
          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
          expect(response.body).to include('<turbo-stream action="replace" target="import">')
          expect(response.body).to include("File uploaded. Starting sync...")
        end

        it "saves the uploaded file into the Rails tmp folder" do
          post import_data_transfers_path, params: { file: file }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          enqueued_job = Sidekiq::Worker.jobs.find { |j| j["class"] == "DataImportJob" }
          saved_path = enqueued_job["args"].first

          expect(saved_path).to start_with(Rails.root.join("tmp/import_").to_s)
          expect(File.exist?(saved_path)).to be true
          expect(File.read(saved_path)).to eq(json_content)

          FileUtils.rm_f(saved_path)
        end
      end

      context "with HTML request" do
        it "enqueues DataImportJob and redirects to data_transfers_path" do
          expect do
            post import_data_transfers_path, params: { file: file }
          end.to change(DataImportJob.jobs, :size).by(1)

          enqueued_job = DataImportJob.jobs.last
          expect(enqueued_job["args"].first).to be_a(String)
          expect(enqueued_job["args"].second).to eq(user.id)

          expect(response).to redirect_to(data_transfers_path)
        end
      end
    end

    context "when no file is uploaded" do
      it "does not enqueue DataImportJob and redirects with alert" do
        expect do
          post import_data_transfers_path, params: { file: nil }
        end.not_to change(DataImportJob.jobs, :size)

        expect(response).to redirect_to(data_transfers_path)
        expect(flash[:alert]).to eq("Please upload a valid JSON file.")
      end
    end
  end

  context "when user is not authenticated" do
    before do
      sign_out user if defined?(sign_out)
    end

    it "redirects GET /data_transfers to sign in page" do
      get data_transfers_path
      expect(response).to have_http_status(:redirect)
    end

    it "redirects POST /data_transfers/export to sign in page" do
      post export_data_transfers_path
      expect(response).to have_http_status(:redirect)
    end

    it "redirects POST /data_transfers/import to sign in page" do
      post import_data_transfers_path
      expect(response).to have_http_status(:redirect)
    end
  end
end
