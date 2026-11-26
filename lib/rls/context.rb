# frozen_string_literal: true

module Rls
  module Context
    extend ActiveSupport::Concern

    module ClassMethods
      # Scope the tenant GUC to a real transaction. RESET first scrubs session-level
      # values left by older builds; a failed cleanup discards the connection.
      def with_rls_user(user_id)
        raw_id = user_id.to_s.strip
        raise ArgumentError, "RLS tenant id must be a positive integer" if raw_id.empty?

        tenant_id = Integer(raw_id, 10)
        raise ArgumentError, "RLS tenant id must be a positive integer" unless tenant_id.positive?

        pool = ActiveRecord::Base.connection_pool
        connection = ActiveRecord::Base.connection

        begin
          connection.execute("RESET app.current_user_id")
        rescue StandardError
          pool.remove(connection)
          raise
        end

        connection.transaction(requires_new: true) do
          quoted_id = connection.quote(tenant_id.to_s)
          connection.select_value("SELECT set_config('app.current_user_id', #{quoted_id}, true)")
          yield
        end
      end

      def current_rls_user_id
        ActiveRecord::Base.connection.select_value("SELECT current_user_id();")
      end
    end

    def with_rls_user(user_id, &)
      self.class.with_rls_user(user_id, &)
    end
  end
end
