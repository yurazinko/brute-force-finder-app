# frozen_string_literal: true

module Rls
  module Context
    extend ActiveSupport::Concern

    class StaleTenantContextError < StandardError; end

    module ClassMethods
      def with_rls_user(user_id)
        tenant_id = normalize_tenant_id(user_id)
        connection = ActiveRecord::Base.connection
        stack = context_stack(connection)
        previous_value = prepare_connection_context(connection, stack)

        run_in_tenant_context(connection, stack, tenant_id, previous_value) { yield }
      end

      def current_rls_user_id
        ActiveRecord::Base.connection.select_value(
          "SELECT NULLIF(current_setting('app.current_user_id', true), '')"
        )
      end

      private

      def normalize_tenant_id(user_id)
        raw_id = user_id.to_s.strip
        raise ArgumentError, "RLS tenant id must be a positive integer" if raw_id.empty?

        tenant_id = Integer(raw_id, 10)
        raise ArgumentError, "RLS tenant id must be a positive integer" unless tenant_id.positive?

        tenant_id
      end

      def prepare_connection_context(connection, stack)
        current_value = current_tenant_value(connection)
        validate_untracked_context!(connection, stack, current_value)
        return current_value if connection.transaction_open?

        connection.execute("RESET app.current_user_id")
        nil
      end

      def current_tenant_value(connection)
        connection.select_value("SELECT NULLIF(current_setting('app.current_user_id', true), '')")
      end

      def validate_untracked_context!(connection, stack, current_value)
        return unless connection.transaction_open? && current_value.present? && stack.empty?

        ActiveRecord::Base.connection_pool.remove(connection)
        raise StaleTenantContextError,
              "Untracked RLS tenant context detected inside an open transaction"
      end

      def run_in_tenant_context(connection, stack, tenant_id, previous_value)
        stack.push(tenant_id)
        connection.transaction(requires_new: true) do
          set_local_tenant(connection, tenant_id)
          result = yield
          restore_previous_tenant(connection, previous_value)
          result
        end
      ensure
        stack.pop
      end

      def set_local_tenant(connection, tenant_id)
        quoted_id = connection.quote(tenant_id.to_s)
        connection.select_value("SELECT set_config('app.current_user_id', #{quoted_id}, true)")
      end

      def restore_previous_tenant(connection, previous_value)
        return reset_tenant(connection) if previous_value.blank?

        quoted_previous = connection.quote(previous_value)
        connection.select_value("SELECT set_config('app.current_user_id', #{quoted_previous}, true)")
      end

      def reset_tenant(connection)
        connection.execute("RESET app.current_user_id")
      end

      def context_stack(connection)
        contexts = ActiveSupport::IsolatedExecutionState[:rls_contexts] ||= {}.compare_by_identity
        unless contexts.compare_by_identity?
          contexts = ActiveSupport::IsolatedExecutionState[:rls_contexts] = contexts.compare_by_identity
        end
        contexts[connection] ||= []
      end
    end

    def with_rls_user(user_id, &)
      self.class.with_rls_user(user_id, &)
    end
  end
end
