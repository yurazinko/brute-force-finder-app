# frozen_string_literal: true

namespace :data_transfers do
  desc "Purge user data exports older than one hour"
  task purge_expired: :environment do
    cutoff = 1.hour.ago
    purged = 0

    ActiveStorage::Attachment.joins(:blob)
                             .where(name: "data_export", record_type: "User")
                             .where(active_storage_blobs: { created_at: ...cutoff })
                             .find_each do |attachment|
      attachment.purge_later
      purged += 1
    end

    puts "Queued #{purged} expired data export(s) for purge."
  end
end
