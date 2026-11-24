# frozen_string_literal: true

require "set"

module Database
  # One allow-list for both UI selection and import/export. Only user-owned,
  # application data is included; users, Active Storage, and infrastructure tables
  # must never be imported from an uploaded backup.
  class DataTransferRegistry
    Entry = Struct.new(:name, :scope, :importer, :dependencies, keyword_init: true)

    ENTRIES = [
      Entry.new(
        name: "categories",
        scope: ->(user) { Category.where(user_id: user.id) },
        importer: Importers::CategoryImporter,
        dependencies: []
      ),
      Entry.new(
        name: "targets",
        scope: ->(user) { Target.joins(:category).where(categories: { user_id: user.id }) },
        importer: Importers::TargetImporter,
        dependencies: %w[categories]
      ),
      Entry.new(
        name: "target_patterns",
        scope: ->(user) { TargetPattern.joins(target: :category).where(categories: { user_id: user.id }) },
        importer: Importers::TargetPatternImporter,
        dependencies: %w[categories targets]
      ),
      Entry.new(
        name: "searches",
        scope: ->(user) { Search.where(user_id: user.id) },
        importer: Importers::SearchImporter,
        dependencies: []
      ),
      Entry.new(
        name: "prompts",
        scope: ->(user) { Prompt.joins(:search).where(searches: { user_id: user.id }) },
        importer: Importers::PromptImporter,
        dependencies: %w[categories targets searches]
      ),
      Entry.new(
        name: "results",
        scope: ->(user) { Result.joins(:search).where(searches: { user_id: user.id }) },
        importer: Importers::ResultImporter,
        dependencies: %w[categories targets searches]
      )
    ].each { |entry| entry.dependencies.freeze; entry.freeze }.freeze

    BY_NAME = ENTRIES.index_by(&:name).freeze

    class << self
      def entries
        ENTRIES
      end

      def table_names
        ENTRIES.map(&:name)
      end

      def include?(table_name)
        BY_NAME.key?(table_name.to_s)
      end

      def fetch(table_name)
        BY_NAME.fetch(table_name.to_s)
      end

      def import_entries
        ENTRIES
      end

      # Include foreign-key dependencies so a partial export remains restorable.
      # The final order always follows the registry's dependency-safe order.
      def resolve_selection(requested_tables)
        return table_names if requested_tables.nil?

        selected = Array(requested_tables).map(&:to_s).select { |name| include?(name) }.to_set
        queue = selected.to_a

        until queue.empty?
          name = queue.shift
          fetch(name).dependencies.each do |dependency|
            next if selected.include?(dependency)

            selected << dependency
            queue << dependency
          end
        end

        table_names.select { |name| selected.include?(name) }
      end
    end
  end
end
