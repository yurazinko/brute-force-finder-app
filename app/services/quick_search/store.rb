# frozen_string_literal: true

require "json"

module QuickSearch
  class Store
    TTL = 1.hour.to_i
    MAX_QUERY_LENGTH = 500
    RESULT_FIELDS = %w[
      url url_hash title content engine status acknowledged relevance_score
      matched_keywords verification_status created_at
    ].freeze

    UPDATE_SCRIPT = <<~LUA
      local raw = redis.call('GET', KEYS[1])
      if not raw then return nil end
      local data = cjson.decode(raw)
      if data['status'] == 'cleared' then return nil end
      local attributes = cjson.decode(ARGV[1])
      for key, value in pairs(attributes) do
        data[key] = value
      end
      local encoded = cjson.encode(data)
      redis.call('SET', KEYS[1], encoded, 'EX', ARGV[2])
      return encoded
    LUA

    COMPLETE_VERIFICATION_SCRIPT = <<~LUA
      local raw = redis.call('GET', KEYS[1])
      if not raw then return nil end

      local data = cjson.decode(raw)
      if data['status'] == 'cleared' then return nil end

      local claimed = redis.call('SET', KEYS[2], '1', 'NX', 'EX', ARGV[1])
      if not claimed then return nil end

      local completed = tonumber(data['verification_completed_count'] or 0) + 1
      local pending = math.max(tonumber(data['verification_pending_count'] or 0) - 1, 0)
      local total = tonumber(data['verification_total_count'] or 0)

      data['verification_completed_count'] = completed
      data['verification_pending_count'] = pending

      if pending == 0 and data['engines_finished'] then
        data['status'] = 'completed'
        data['active_engine'] = cjson.null
        data['message'] = 'Search complete — ' .. tostring(tonumber(data['results_count'] or 0)) .. ' results found.'
      else
        data['status'] = 'verifying'
        data['active_engine'] = 'Verification'
        data['message'] = 'Verifying results (' .. tostring(completed) .. '/' .. tostring(total) .. ')…'
      end

      local encoded = cjson.encode(data)
      redis.call('SET', KEYS[1], encoded, 'EX', ARGV[1])
      return encoded
    LUA

    APPEND_RESULTS_SCRIPT = <<~LUA
      local raw = redis.call('GET', KEYS[1])
      if not raw then return 0 end

      local data = cjson.decode(raw)
      if data['status'] == 'cleared' then return 0 end

      for index = 2, #ARGV do
        redis.call('RPUSH', KEYS[2], ARGV[index])
      end
      redis.call('EXPIRE', KEYS[2], ARGV[1])
      return #ARGV - 1
    LUA

    class << self
      def create!(token:, user_id:, query:)
        validate_token!(token)
        data = {
          "token" => token,
          "user_id" => user_id,
          "query" => query,
          "status" => "queued",
          "message" => "Preparing your search…",
          "active_engine" => nil,
          "results_count" => 0,
          "failed_engines" => [],
          "engines_finished" => false,
          "verification_total_count" => 0,
          "verification_completed_count" => 0,
          "verification_pending_count" => 0
        }

        Sidekiq.redis do |redis|
          redis.multi do |transaction|
            transaction.set(data_key(token), JSON.generate(data), ex: TTL)
            transaction.del(results_key(token))
          end
        end

        data
      end

      def fetch(token, user_id: :any)
        return if token.blank? || !valid_token?(token)

        data = read_data(token)
        return unless data
        return if data["status"] == "cleared"
        return if user_id != :any && data["user_id"].to_s != user_id.to_s

        data
      end

      def update!(token, attributes)
        return unless valid_token?(token)

        serialized = Sidekiq.redis do |redis|
          eval_script(
            redis,
            UPDATE_SCRIPT,
            keys: [data_key(token)],
            argv: [JSON.generate(attributes.stringify_keys), TTL]
          )
        end
        serialized.present? ? JSON.parse(serialized) : nil
      rescue JSON::ParserError
        nil
      end

      def append_results(token, records)
        return if records.blank? || !valid_token?(token)

        serialized = records.map do |record|
          record.stringify_keys.slice(*RESULT_FIELDS).to_json
        end

        Sidekiq.redis do |redis|
          eval_script(
            redis,
            APPEND_RESULTS_SCRIPT,
            keys: [data_key(token), results_key(token)],
            argv: [TTL, *serialized]
          )
        end
      end

      def clear!(token)
        return false unless valid_token?(token)

        hashes = results(token).filter_map { |record| record["url_hash"] }
        updated = update!(
          token,
          status: "cleared",
          active_engine: nil,
          message: "Quick Search results cleared.",
          results_count: 0,
          verification_pending_count: 0
        )
        keys = [results_key(token), *hashes.map { |url_hash| verification_done_key(token, url_hash) }]
        Sidekiq.redis { |redis| redis.del(*keys) }
        updated.present?
      end

      def results(token, user_id: :any)
        return [] unless fetch(token, user_id: user_id)

        entries = Sidekiq.redis { |redis| redis.lrange(results_key(token), 0, -1) }
        entries.filter_map do |entry|
          JSON.parse(entry)
        rescue JSON::ParserError
          nil
        end
      end

      def result(token, url_hash:, user_id: :any)
        results(token, user_id: user_id).find { |record| record["url_hash"] == url_hash }
      end

      def update_result!(token, url_hash:, attributes:)
        return unless valid_token?(token)

        updated_record = nil
        Sidekiq.redis do |redis|
          entries = redis.lrange(results_key(token), 0, -1)
          index = entries.index do |entry|
            JSON.parse(entry)["url_hash"] == url_hash
          rescue JSON::ParserError
            false
          end
          next unless index

          updated_record = JSON.parse(entries[index]).merge(attributes.stringify_keys)
          redis.lset(results_key(token), index, JSON.generate(updated_record))
          redis.expire(results_key(token), TTL)
        end
        updated_record
      rescue JSON::ParserError
        nil
      end

      def begin_verifications!(token, total)
        update!(
          token,
          status: "verifying",
          active_engine: "Verification",
          message: "Verifying #{total} results…",
          engines_finished: true,
          verification_total_count: total,
          verification_completed_count: 0,
          verification_pending_count: total
        )
      end

      def complete_verification!(token, url_hash:)
        return unless valid_token?(token)

        serialized = Sidekiq.redis do |redis|
          eval_script(
            redis,
            COMPLETE_VERIFICATION_SCRIPT,
            keys: [data_key(token), verification_done_key(token, url_hash)],
            argv: [TTL]
          )
        end
        serialized.present? ? JSON.parse(serialized) : nil
      rescue JSON::ParserError
        nil
      end

      private

      # Sidekiq 8 uses RedisClient rather than redis-rb. Its compatibility
      # adapter forwards unknown commands as raw Redis commands, so the
      # redis-rb-style eval(script, keys:, argv:) API is not supported here.
      # Send the Redis EVAL command with a flattened argument list instead.
      def eval_script(redis, script, keys:, argv:)
        redis.call("EVAL", script, keys.size.to_s, *keys, *argv.map(&:to_s))
      end

      def read_data(token)
        serialized = Sidekiq.redis { |redis| redis.get(data_key(token)) }
        serialized.present? ? JSON.parse(serialized) : nil
      rescue JSON::ParserError
        nil
      end

      def data_key(token) = "quick_search:v1:#{token}:data"

      def results_key(token) = "quick_search:v1:#{token}:results"

      def verification_done_key(token, url_hash) = "quick_search:v1:#{token}:verification:#{url_hash}"

      def valid_token?(token) = token.to_s.match?(/\A[a-f0-9]{32}\z/)

      def validate_token!(token)
        raise ArgumentError, "Invalid quick search token" unless valid_token?(token)
      end
    end
  end
end
