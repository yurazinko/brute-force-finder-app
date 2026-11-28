# frozen_string_literal: true

module Database
  module DataImport
    class TableValidator
      def validate_ndjson_tables!(table_names)
        validate_supported_tables!(table_names)
        validate_unique_tables!(table_names)
        validate_registry_order!(table_names)
        validate_dependency_closure!(table_names)
      end

      def validate_legacy_tables!(entries, provided_names)
        validate_supported_tables!(provided_names)
        validate_unique_tables!(provided_names)
        validate_dependency_closure!(provided_names)
        validate_entry_dependencies!(entries, provided_names)
      end

      private

      def validate_supported_tables!(table_names)
        unknown_tables = table_names.reject { |name| DataTransferRegistry.include?(name) }
        return if unknown_tables.empty?

        raise ArgumentError, "Backup contains unsupported tables: #{unknown_tables.uniq.join(', ')}"
      end

      def validate_unique_tables!(table_names)
        return if table_names.uniq == table_names

        raise ArgumentError, "Backup declares duplicate table names."
      end

      def validate_registry_order!(table_names)
        registry_order = DataTransferRegistry.table_names
        sorted_names = table_names.sort_by { |name| registry_order.index(name) || Float::INFINITY }
        return if sorted_names == table_names

        raise ArgumentError, "Backup table declarations are not in dependency-safe order."
      end

      def validate_dependency_closure!(table_names)
        expanded = DataTransferRegistry.resolve_selection(table_names)
        missing_dependencies = expanded - table_names
        return if missing_dependencies.empty?

        raise ArgumentError, "Backup is missing dependencies: #{missing_dependencies.join(', ')}"
      end

      def validate_entry_dependencies!(entries, provided_names)
        entries.each do |entry|
          missing = entry.dependencies.reject { |dependency| provided_names.include?(dependency) }
          next if missing.empty?

          raise ArgumentError, "Backup table '#{entry.name}' is missing dependencies: #{missing.join(', ')}"
        end
      end
    end
  end
end
