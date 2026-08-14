# frozen_string_literal: true

module Database
  module Importers
    class BaseImporter
      attr_reader :records, :target_user_id, :id_maps

      def initialize(records, target_user_id, id_maps)
        @records = records
        @target_user_id = target_user_id
        @id_maps = id_maps
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end
    end
  end
end
