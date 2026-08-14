# frozen_string_literal: true

module Rls
  module Sidekiq
    class ServerMiddleware
      include Rls::Context

      def call(worker, job, _queue, &)
        return yield unless worker.is_a?(Rls::Sidekiq)

        user_id = extract_user_id(worker, job["args"])
        with_rls_user(user_id, &)
      end

      private

      def extract_user_id(worker, args)
        extract_from_hash(args) ||
          extract_by_param_name(worker, args) ||
          extract_single_id(args)
      end

      def extract_from_hash(args)
        hash = args.find { |arg| arg.is_a?(Hash) } || {}
        hash.with_indifferent_access.slice(:user_id, :_user_id).values.compact.first
      end

      def extract_by_param_name(worker, args)
        index = worker.method(:perform).parameters.index { |_, name| name.to_s.end_with?("user_id") }
        args[index] if index
      end

      def extract_single_id(args)
        args.first if args.one? && args.first.to_s.match?(/^\d+$/)
      end
    end
  end
end
