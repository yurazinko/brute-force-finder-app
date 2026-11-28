# frozen_string_literal: true

module Database
  module DataImport
    class AdvisoryLock
      LOCK_NAMESPACE = 729_194

      def self.synchronize(user_id, &)
        new(user_id).synchronize(&)
      end

      def initialize(user_id)
        @user_id = Integer(user_id)
      end

      def synchronize
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          acquire(connection)
          begin
            yield
          ensure
            release(connection)
          end
        end
      end

      private

      def acquire(connection)
        connection.select_value(lock_sql("pg_advisory_lock"))
      end

      def release(connection)
        connection.select_value(lock_sql("pg_advisory_unlock"))
      rescue StandardError
        ActiveRecord::Base.connection_pool.remove(connection)
        raise
      end

      def lock_sql(function)
        "SELECT #{function}(#{LOCK_NAMESPACE}, #{@user_id})"
      end
    end
  end
end
