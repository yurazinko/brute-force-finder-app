# frozen_string_literal: true

module Results
  class BatchPersister
    def self.call(search_id, result_records) = new(search_id, result_records).call

    def initialize(search_id, result_records)
      @search_id = search_id
      @result_records = result_records
    end

    def call
      return { raw_count: 0, new_count: 0 } if @result_records.blank?

      records = prepare_records(@result_records)
      records = deduplicate_by_hash(records)

      existing_db_records = fetch_existing_records(records)

      existing_in_current_search = existing_db_records.select do |r|
        r["search_id"] == @search_id
      end.pluck("url_hash").to_set
      new_count = records.count { |r| existing_in_current_search.exclude?(r["url_hash"]) }

      global_ack_set = existing_db_records.select { |r| r["acknowledged"] == true }.to_set { |r| r["url_hash"] }
      enriched_records = records.map { |r| build_db_payload(r, global_ack_set) }

      execute_upsert(enriched_records)

      {
        raw_count: @result_records.size,
        new_count: new_count
      }
    end

    private

    def prepare_records(records)
      records.map { |r| r.transform_keys(&:to_s) }
    end

    def deduplicate_by_hash(records)
      records.group_by { |r| r["url_hash"] }.values.map(&:first)
    end

    def fetch_existing_records(records)
      incoming_hashes = records.pluck("url_hash")
      incoming_hashes.compact!
      incoming_hashes.uniq!

      Result.unscoped
            .where(url_hash: incoming_hashes)
            .pluck(:search_id, :url_hash, :acknowledged)
            .map do |search_id, url_hash, ack|
        { "search_id" => search_id, "url_hash" => url_hash,
          "acknowledged" => ack }
      end
    end

    def build_db_payload(record, global_ack_set)
      {
        "search_id" => @search_id,
        "url" => record["url"],
        "url_hash" => record["url_hash"],
        "title" => record["title"],
        "content" => record["content"],
        "status" => record["status"] || "unread",
        "acknowledged" => global_ack_set.include?(record["url_hash"]),
        "created_at" => record["created_at"] || Time.current,
        "updated_at" => record["updated_at"] || Time.current
      }
    end

    def execute_upsert(enriched_records)
      ActiveRecord::Base.transaction(requires_new: true) do
        Result.upsert_all(enriched_records, unique_by: %i[search_id url_hash])
      end
    end
  end
end
