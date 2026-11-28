# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Data export downloads", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }

  before do
    user.data_export.attach(
      io: StringIO.new('{"_format":"brute-force-finder-ndjson"}'),
      filename: "backup.ndjson",
      content_type: "application/x-ndjson"
    )
  end

  it "requires an authenticated session" do
    get data_transfers_download_path
    expect(response).to have_http_status(:found)
  end

  it "streams only the signed-in user's export through the application" do
    sign_in user

    get data_transfers_download_path

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to include("brute-force-finder-ndjson")
  end

  it "does not expose exports older than one hour" do
    blob = user.data_export.blob
    blob.update_column(:created_at, 2.hours.ago)
    sign_in user

    expect(blob).to receive(:purge_later)
    get data_transfers_download_path

    expect(response).to have_http_status(:not_found)
  end
end
