# frozen_string_literal: true

module Rls
  module Context
    extend ActiveSupport::Concern

    class StaleTenantContextError < StandardError; end

    module ClassMethods
      def with_rls_user(user_id)
        raw_id = user_id.to_s.strip
        raise ArgumentError, "RLS tenant id must be a positive integer" if raw_id.empty?

        tenant_id = Integer(raw_id, 10)
        raise ArgumentError, "RLS tenant id must be a positive integer" unless tenant_id.positive?

        pool = ActiveRecord::Base.connection_pool
        connection = ActiveRecord::Base.connection

        stack = context_stack(connection)

        current_value = connection.select_value(
          "SELECT NULLIF(current_setting('app.current_user_id', true), '')"
        )

        # A tenant inside an open transaction must belong to a context
        # managed by this module. Otherwise the connection is unsafe.
        if connection.transaction_open? && current_value.present? && stack.empty?
          pool.remove(connection)
          raise StaleTenantContextError,
                "Untracked RLS tenant context detected inside an open transaction"
        end

        # Scrub session-level settings only when no transaction is open.
        unless connection.transaction_open?
          connection.execute("RESET app.current_user_id")
          current_value = nil
        end

        previous_value = current_value
        stack.push(tenant_id)

        begin
          connection.transaction(requires_new: true) do
            quoted_id = connection.quote(tenant_id.to_s)

            connection.select_value(
              "SELECT set_config('app.current_user_id', #{quoted_id}, true)"
            )

            result = yield

            # Restore the parent tenant only after successful execution.
            # If yield raises, PostgreSQL rolls back the savepoint,
            # automatically restoring the previous SET LOCAL value.
            if previous_value.present?
              quoted_previous = connection.quote(previous_value)

              connection.select_value(
                "SELECT set_config('app.current_user_id', #{quoted_previous}, true)"
              )
            else
              connection.execute("RESET app.current_user_id")
            end

            result
          end
        ensure
          stack.pop
        end
      end

      def current_rls_user_id
        ActiveRecord::Base.connection.select_value(
          "SELECT NULLIF(current_setting('app.current_user_id', true), '')"
        )
      end

      private

      def context_stack(connection)
        contexts = ActiveSupport::IsolatedExecutionState[:rls_contexts] ||= {}
        contexts[connection.object_id] ||= []
      end
    end

    def with_rls_user(user_id, &)
      self.class.with_rls_user(user_id, &)
    end
  end
end
