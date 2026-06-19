# frozen_string_literal: true

require "rails_helper"
require "sidekiq/cron/job"

RSpec.describe "Sidekiq Cron Schedule" do
  it "has valid nightly scraping cron configuration" do
    Sidekiq::Cron::Job.load_from_hash(YAML.load_file(Rails.root.join("config/sidekiq.yml"))[:scheduler][:schedule])

    cron_job = Sidekiq::Cron::Job.find("nightly_scraping")

    expect(cron_job).to be_present
    expect(cron_job.cron).to eq("0 2 * * *")
    expect(cron_job.klass).to eq("NightlyScrapingCronJob")
  end
end
