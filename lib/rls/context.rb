# frozen_string_literal: true

module Rls
  module Context
    extend ActiveSupport::Concern

    module ClassMethods
      def with_rls_user(user_id)
        formatted_id = user_id.presence.to_s

        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array(["SET LOCAL app.current_user_id = ?", formatted_id])
          )
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
