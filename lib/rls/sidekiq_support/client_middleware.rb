# frozen_string_literal: true

module Rls
  module SidekiqSupport
    class ClientMiddleware
      class MissingTenantContextError < StandardError; end

      TENANT_ARGUMENT_NAMES = %i[user_id _user_id].freeze

      def call(worker_class, job, _queue, _redis_pool = nil)
        klass = resolve_worker_class(worker_class, job)
        return yield unless rls_scoped_worker?(klass)

        tenant_id = job["rls_user_id"].presence || tenant_from_declared_argument(klass, worker_arguments(job))
        # Chained jobs may intentionally omit user_id (for example, a retry
        # scheduled by Results::VerificationJob). Inherit only the active database
        # tenant, never infer it from an arbitrary numeric job argument.
        tenant_id ||= current_database_tenant_id
        if tenant_id.blank?
          raise MissingTenantContextError,
                "RLS-scoped job #{klass.name} requires an explicit or active RLS tenant"
        end

        normalized_tenant_id = Integer(tenant_id.to_s, 10)
        raise MissingTenantContextError, "RLS tenant id must be positive" unless normalized_tenant_id.positive?

        job["rls_user_id"] = normalized_tenant_id
        yield
      end

      private

      def resolve_worker_class(worker_class, job)
        # ActiveJob is serialized by Sidekiq as JobWrapper with the real class
        # in `wrapped`; direct Sidekiq workers use `class`.
        class_name = job["wrapped"].presence || job["class"].presence
        return class_name.constantize if class_name.present?

        return worker_class if worker_class.is_a?(Class)

        worker_class.to_s.constantize
      end

      def rls_scoped_worker?(klass)
        klass.ancestors.include?(Rls::SidekiqSupport)
      end

      # This is a declared parameter-name contract, not a numeric/shape heuristic.
      # SearchCampaigns::ActivationJob(search_id, _user_id) therefore uses the second argument.
      def current_database_tenant_id
        ActiveRecord::Base.connection.select_value("SELECT current_user_id()")
      end

      def worker_arguments(job)
        args = job.fetch("args", [])
        return args if job["wrapped"].blank?

        active_job_payload = args.first
        if active_job_payload.is_a?(Hash) && active_job_payload["arguments"].is_a?(Array)
          return active_job_payload["arguments"]
        end

        args
      end

      def tenant_from_declared_argument(klass, args)
        parameters = klass.instance_method(:perform).parameters
        positional_index = parameters.index do |kind, name|
          %i[req opt].include?(kind) && TENANT_ARGUMENT_NAMES.include?(name)
        end
        return args[positional_index] if positional_index

        keyword_parameter = parameters.find do |kind, name|
          %i[key keyreq].include?(kind) && TENANT_ARGUMENT_NAMES.include?(name)
        end
        return unless keyword_parameter

        args.rfind { |arg| arg.is_a?(Hash) }&.with_indifferent_access&.[](keyword_parameter.last)
      end
    end
  end
end
