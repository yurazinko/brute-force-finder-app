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

    class << self
      def create!(token:, user_id:, query:)
        validate_token!(token)
        data = {
          "token" => token,
          "user_id" => user_id.to_i,
          "query" => query,
          "status" => "queued",
          "message" => "Preparing your search…",
          "active_engine" => nil,
          "results_count" => 0,
          "failed_engines" => []
        }

        Sidekiq.redis do |redis|
          redis.multi do |transaction|
            transaction.set(data_key(token), JSON.generate(data), ex: TTL)
            transaction.del(results_key(token))
          end
        end

        data
      end

      def fetch(token, user_id:)
        return if token.blank? || !valid_token?(token)

        data = read_data(token)
        return unless data && data["user_id"].to_i == user_id.to_i

        data
      end

      def update!(token, attributes)
        data = read_data(token)
        return unless data

        data.merge!(attributes.stringify_keys)
        write_data(token, data)
        data
      end

      def append_results(token, records)
        return if records.blank? || !valid_token?(token)

        serialized = records.map do |record|
          record.stringify_keys.slice(*RESULT_FIELDS).to_json
        end

        Sidekiq.redis do |redis|
          redis.rpush(results_key(token), *serialized)
          redis.expire(results_key(token), TTL)
        end
      end

      def results(token, user_id:)
        return [] unless fetch(token, user_id: user_id)

        entries = Sidekiq.redis { |redis| redis.lrange(results_key(token), 0, -1) }
        entries.filter_map do |entry|
          JSON.parse(entry)
        rescue JSON::ParserError
          nil
        end
      end

      private

      def read_data(token)
        serialized = Sidekiq.redis { |redis| redis.get(data_key(token)) }
        serialized.present? ? JSON.parse(serialized) : nil
      rescue JSON::ParserError
        nil
      end

      def write_data(token, data)
        Sidekiq.redis { |redis| redis.set(data_key(token), JSON.generate(data), ex: TTL) }
      end

      def data_key(token) = "quick_search:v1:#{token}:data"

      def results_key(token) = "quick_search:v1:#{token}:results"

      def valid_token?(token) = token.to_s.match?(/\A[a-f0-9]{32}\z/)

      def validate_token!(token)
        raise ArgumentError, "Invalid quick search token" unless valid_token?(token)
      end
    end
  end
end
