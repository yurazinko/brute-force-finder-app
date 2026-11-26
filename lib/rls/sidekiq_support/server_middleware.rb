# frozen_string_literal: true

module Rls
  module SidekiqSupport
    class ServerMiddleware
      include Rls::Context

      class MissingTenantContextError < StandardError; end

      def call(worker, job, _queue, &)
        klass = resolve_worker_class(worker, job)
        return yield unless klass.ancestors.include?(Rls::SidekiqSupport)

        user_id = job["rls_user_id"]
        if user_id.blank?
          raise MissingTenantContextError,
                "Missing explicit rls_user_id in Sidekiq payload for #{worker.class.name}"
        end

        with_rls_user(user_id, &)
      end

      private

      def resolve_worker_class(worker, job)
        wrapped_class = job["wrapped"].presence
        return wrapped_class.constantize if wrapped_class.present?

        return worker if worker.is_a?(Class)

        worker.class
      end
    end
  end
end
