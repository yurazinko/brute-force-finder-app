# frozen_string_literal: true

module Results
  class BatchPersister
    BATCH_SIZE = 100
    UI_ATTRIBUTES = %i[id search_id url url_hash title content engine status acknowledged
                       relevance_score verification_status matched_keywords created_at].freeze

    def self.call(search, prompt, result_records) = new(search, prompt, result_records).call

    def initialize(search, prompt, result_records)
      @search = search
      @search_id = search.id
      @prompt =  prompt
      @target = prompt&.target
      @result_records = result_records
    end

    def call
      return { raw_count: 0, new_count: 0, persisted_results: [] } if @result_records.blank?

      total_new = 0
      all_persisted = []
      prepare_and_deduplicate(@result_records).each_slice(BATCH_SIZE) do |batch|
        new_c, persisted = process_batch(batch)
        total_new += new_c
        all_persisted.concat(persisted)
      end

      { raw_count: @result_records.size, new_count: total_new, persisted_results: all_persisted }
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
      existing = fetch_existing_records(batch)
      [calculate_new_records(batch, existing), persist_records!(batch, existing)]
    end

    def fetch_existing_records(batch)
      hashes = batch.filter_map { |r| r["url_hash"] }
      hashes = hashes.uniq
      hashes.empty? ? [] : Result.unscoped.where(url_hash: hashes).pluck(:search_id, :url_hash, :acknowledged)
    end

    def calculate_new_records(batch, existing)
      search_hashes = existing.each_with_object(Set.new) { |(id, h), set| set << h if id == @search_id }
      batch.count { |r| search_hashes.exclude?(r["url_hash"]) }
    end

    def persist_records!(batch, existing)
      global_ack = existing.each_with_object(Set.new) { |(_, h, ack), set| set << h if ack == true }
      execute_upsert(batch.map { |r| build_db_payload(r, global_ack) })
    end

    def build_db_payload(record, global_ack_set) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
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
        "target_id" => @target&.id,
        "target_domain" => @target&.domain,
        "target_pattern" => record["target_pattern"],
        "created_at" => record["created_at"] || current_time,
        "updated_at" => record["updated_at"] || current_time
      }
    end

    def execute_upsert(enriched_records)
      inserted_rows = []

      ActiveRecord::Base.transaction(requires_new: true) do
        result_data = Result.upsert_all(
          enriched_records,
          unique_by: %i[search_id url_hash],
          update_only: %i[title content engine relevance_score matched_keywords verification_status],
          returning: %i[id verification_status]
        )

        inserted_rows = result_data.rows.map { |id, status| { id: id, status: status } }
      end

      schedule_for_verification(inserted_rows)

      inserted_ids = inserted_rows.pluck(:id)
      Result.select(UI_ATTRIBUTES)
            .where(id: inserted_ids, acknowledged: [false, @search.show_acknowledged].uniq)
            .to_a
    end

    def schedule_for_verification(inserted_rows)
      inserted_rows.each do |row|
        if row[:status] == "pending" || row[:status].to_s.start_with?("unverified")
          ResultVerificationJob.perform_async(row[:id], @search.user_id)
        end
      end
    end
  end
end
