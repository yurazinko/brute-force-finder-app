# frozen_string_literal: true

module Database
  module DataImport
    class ProgressReporter
      def initialize(callback)
        @callback = callback
      end

      def table_started(table_name, index, total)
        return unless @callback

        progress = total.zero? ? 95 : ((index.to_f / total) * 95).to_i
        @callback.call(progress, "Importing #{table_name}...")
      end
    end
  end
end
