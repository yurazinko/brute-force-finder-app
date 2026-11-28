# frozen_string_literal: true

module Results
  class BatchPersister
    include Rls::Context

    BATCH_SIZE = 100
    UI_ATTRIBUTES = %i[id search_id url url_hash title content engine status acknowledged
                       relevance_score verification_status matched_keywords created_at].freeze
    ON_DUPLICATE_SQL = Arel.sql(<<~SQL.squish)
      title = EXCLUDED.title,
      content = EXCLUDED.content,
      engine = EXCLUDED.engine,
      matched_keywords = EXCLUDED.matched_keywords,
      relevance_score = CASE
        WHEN results.verification_status = 'verified'
          AND EXCLUDED.verification_status <> 'verified'
        THEN results.relevance_score
        ELSE EXCLUDED.relevance_score
      END,
      verification_status = CASE
        WHEN results.verification_status = 'verified'
          AND EXCLUDED.verification_status <> 'verified'
        THEN results.verification_status
        ELSE EXCLUDED.verification_status
      END,
      updated_at = EXCLUDED.updated_at
    SQL

    def self.call(search, prompt, result_records) = new(search, prompt, result_records).call

    def initialize(search, prompt, result_records)
      @search = search
      @search_id = search.id
      @prompt =  prompt
      @target = prompt&.target
      @result_records = result_records
    end

    def call
      return empty_result if @result_records.blank?

      with_rls_user(tenant_id) { persist_all_batches }
    end

    private

    def empty_result
      { raw_count: 0, new_count: 0, persisted_results: [] }
    end

    def tenant_id
      active_tenant_id = self.class.current_rls_user_id
      search_tenant_id = @search.user_id
      validate_tenant_ownership!(active_tenant_id, search_tenant_id)
      search_tenant_id.presence || active_tenant_id
    end

    def validate_tenant_ownership!(active_tenant_id, search_tenant_id)
      return unless active_tenant_id.present? && search_tenant_id.present?
      return if active_tenant_id.to_s == search_tenant_id.to_s

      raise Rls::Context::StaleTenantContextError, "Search owner does not match the active RLS tenant"
    end

    def persist_all_batches
      total_new = 0
      all_persisted = []
      prepare_and_deduplicate(@result_records).each_slice(BATCH_SIZE) do |batch|
        new_count, persisted = process_batch(batch)
        total_new += new_count
        all_persisted.concat(persisted)
      end

      { raw_count: @result_records.size, new_count: total_new, persisted_results: all_persisted }
    end

    def prepare_and_deduplicate(records)
      records.each_with_object({}) do |record, acc|
        normalized = record.with_indifferent_access.symbolize_keys
        hash = normalized[:url_hash]
        acc[hash] ||= normalized if hash.present?
      end.values
    end

    def process_batch(batch)
      existing = fetch_existing_records(batch)
      [calculate_new_records(batch, existing), persist_records!(batch, existing)]
    end

    def persist_records!(batch, existing)
      existing_search_hashes = existing.each_with_object(Set.new) do |(search_id, h, _), set|
        set << h if search_id == @search_id
      end
      global_ack = existing.each_with_object(Set.new) { |(_, h, ack), set| set << h if ack == true }

      execute_upsert(batch.map { |r| build_db_payload(r, global_ack) }, existing_search_hashes)
    end

    def fetch_existing_records(batch)
      hashes = batch.filter_map { |r| r[:url_hash] }
      hashes = hashes.uniq
      return [] if hashes.empty?

      Result.unscoped.joins(:search)
            .where(searches: { user_id: @search.user_id })
            .where(url_hash: hashes)
            .pluck(:search_id, :url_hash, :acknowledged)
    end

    def calculate_new_records(batch, existing)
      search_hashes = existing.each_with_object(Set.new) { |(id, h), set| set << h if id == @search_id }
      batch.count { |r| search_hashes.exclude?(r[:url_hash]) }
    end

    def build_db_payload(record, global_ack_set) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      current_time = Time.current
      url_hash = record[:url_hash]

      {
        search_id: @search_id,
        url: record[:url],
        url_hash: url_hash,
        title: record[:title],
        content: record[:content],
        engine: record[:engine],
        status: record[:status] || "unread",
        acknowledged: global_ack_set.include?(url_hash),
        relevance_score: record[:relevance_score] || 0,
        matched_keywords: record[:matched_keywords] || [],
        verification_status: record[:verification_status] || "pending",
        target_id: @target&.id,
        target_domain: @target&.domain,
        target_pattern: record[:target_pattern],
        created_at: record[:created_at] || current_time,
        updated_at: record[:updated_at] || current_time
      }
    end

    def execute_upsert(enriched_records, existing_search_hashes = Set.new)
      inserted_rows = upsert_records(enriched_records)
      schedule_for_verification(inserted_rows, existing_search_hashes)
      fetch_persisted_results(inserted_rows)
    end

    def upsert_records(enriched_records)
      result_data = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        result_data = Result.upsert_all(
          enriched_records,
          unique_by: %i[search_id url_hash],
          on_duplicate: ON_DUPLICATE_SQL,
          record_timestamps: false,
          returning: %i[id url_hash verification_status]
        )
      end
      result_data.rows.map { |id, url_hash, status| { id: id, url_hash: url_hash, status: status } }
    end

    def fetch_persisted_results(inserted_rows)
      inserted_ids = inserted_rows.pluck(:id)
      Result.select(UI_ATTRIBUTES)
            .where(id: inserted_ids, acknowledged: [false, @search.show_acknowledged].uniq)
            .to_a
    end

    def schedule_for_verification(inserted_rows, existing_search_hashes)
      inserted_rows.each do |row|
        next if existing_search_hashes.include?(row[:url_hash])

        if row[:status] == "pending" || row[:status].to_s.start_with?("unverified")
          Results::VerificationJob.perform_async(row[:id], @search.user_id)
        end
      end
    end
  end
end
