# frozen_string_literal: true

module Results
  class BatchPersister
    BATCH_SIZE = 100

    UI_ATTRIBUTES = %i[id search_id url url_hash title content engine status acknowledged relevance_score
                       verification_status matched_keywords created_at].freeze

    def self.call(search, result_records) = new(search, result_records).call

    def initialize(search, result_records)
      @search = search
      @search_id = search.id
      @result_records = result_records
    end

    def call
      return { raw_count: 0, new_count: 0, persisted_results: [] } if @result_records.blank?

      total_new_count = 0
      all_persisted_results = []

      deduplicated_records = prepare_and_deduplicate(@result_records)

      deduplicated_records.each_slice(BATCH_SIZE) do |batch|
        batch_new_count, batch_persisted = process_batch(batch)
        total_new_count += batch_new_count
        all_persisted_results.concat(batch_persisted)
      end

      {
        raw_count: @result_records.size,
        new_count: total_new_count,
        persisted_results: all_persisted_results
      }
    end

    private

    def prepare_and_deduplicate(records)
      records.each_with_object({}) do |record, acc|
        stringified = record.transform_keys(&:to_s)
        hash = stringified["url_hash"]
        acc[hash] ||= stringified if hash.present?
      end.values
    end

    def process_batch(batch)
      existing_db_records = fetch_existing_records(batch)
      new_count = calculate_new_records(batch, existing_db_records)

      inserted_records = persist_records!(batch, existing_db_records)
      [new_count, inserted_records]
    end

    def fetch_existing_records(batch)
      incoming_hashes = batch.filter_map { |r| r["url_hash"] }.uniq
      return [] if incoming_hashes.empty?

      Result.unscoped
            .where(url_hash: incoming_hashes)
            .pluck(:search_id, :url_hash, :acknowledged)
    end

    def calculate_new_records(batch, existing_db_records)
      existing_in_current_search = existing_db_records.each_with_object(Set.new) do |(id, hash, _ack), set|
        set << hash if id == @search_id
      end

      batch.count { |r| existing_in_current_search.exclude?(r["url_hash"]) }
    end

    def persist_records!(batch, existing_db_records)
      global_ack_set = existing_db_records.each_with_object(Set.new) do |(_id, hash, ack), set|
        set << hash if ack == true
      end

      enriched_records = batch.map { |r| build_db_payload(r, global_ack_set) }
      execute_upsert(enriched_records)
    end

    def build_db_payload(record, global_ack_set) # rubocop:disable Metrics/MethodLength
      current_time = Time.current
      url_hash = record["url_hash"]

      {
        "search_id" => @search_id,
        "url" => record["url"],
        "url_hash" => url_hash,
        "title" => record["title"],
        "content" => record["content"],
        "engine" => record["engine"],
        "status" => record["status"] || "unread",
        "acknowledged" => global_ack_set.include?(url_hash),
        "relevance_score" => record["relevance_score"] || 0,
        "matched_keywords" => record["matched_keywords"] || [],
        "verification_status" => record["verification_status"] || "pending",
        "created_at" => record["created_at"] || current_time,
        "updated_at" => record["updated_at"] || current_time
      }
    end

    def execute_upsert(enriched_records)
      ActiveRecord::Base.transaction(requires_new: true) do
        result_data = Result.upsert_all(
          enriched_records,
          unique_by: %i[search_id url_hash],
          update_only: %i[title content engine relevance_score matched_keywords verification_status],
          returning: %i[id]
        )

        inserted_ids = result_data.pluck("id")

        Result.select(UI_ATTRIBUTES)
              .where(id: inserted_ids, acknowledged: [false, @search.show_acknowledged].uniq)
              .to_a
      end
    end
  end
end
