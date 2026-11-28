# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"
require_relative "../support/capybara_cuprite"
require_relative "../support/system_test_helpers"

RSpec.describe "Database Sync & Backups", type: :system do
  let!(:user) { create_system_user }

  before do
    sign_in_through_ui(user)
    Sidekiq::Testing.fake!
    Database::DataExportJob.jobs.clear
    Database::DataImportJob.jobs.clear
  end

  after do
    Database::DataExportJob.jobs.clear
    Database::DataImportJob.jobs.clear
  end

  it "opens the Sync page and displays all registered export tables" do
    visit data_transfers_path

    expect(page).to have_css("h1", text: "Database Sync & Backups")
    expect(page).to have_content("Export Database Backup")
    expect(page).to have_content("Import & Upsert Sync")

    find("summary", text: "Select Specific Tables").click
    Database::DataTransferRegistry.table_names.each do |table_name|
      expect(page).to have_field(table_name, type: :checkbox)
    end
  end

  it "queues an export after the user selects tables" do
    visit data_transfers_path
    find("summary", text: "Select Specific Tables").click
    uncheck "results"
    click_button "Launch Export"

    expect(Database::DataExportJob.jobs.size).to eq(1)
    args = Database::DataExportJob.jobs.last.fetch("args")
    expect(args.first).to eq(user.id)
    expect(args.second).not_to include("results")
    expect(args.second).to include("categories")
  end

  it "uploads a backup file and queues an import" do
    visit data_transfers_path
    attach_file(
      "Backup JSON / NDJSON File",
      Rails.root.join("spec/fixtures/files/system-test-backup.ndjson")
    )
    click_button "Upload & Sync Database"

    expect(Database::DataImportJob.jobs.size).to eq(1)
    args = Database::DataImportJob.jobs.last.fetch("args")
    expect(args.second).to eq(user.id)
    expect(File).to exist(args.first)
    expect(File.read(args.first)).to include('"_format":"brute-force-finder-ndjson"')
  ensure
    FileUtils.rm_f(args.first) if defined?(args) && args.present?
  end

  it "shows a validation message when the import form is submitted without a file" do
    visit data_transfers_path
    click_button "Upload & Sync Database"

    expect(page).to have_content("Please upload a valid JSON file.")
    expect(Database::DataImportJob.jobs).to be_empty
  end
end
