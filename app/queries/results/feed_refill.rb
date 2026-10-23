# frozen_string_literal: true

module Results
  class FeedRefill
    def self.next_card(base_scope:, removed_id:, options:, visible_ids: [], search: nil)
      new(
        base_scope: base_scope,
        removed_id: removed_id,
        visible_ids: visible_ids,
        options: options,
        search: search
      ).call
    end

    def initialize(base_scope:, removed_id:, visible_ids:, options:, search: nil)
      @base_scope = base_scope
      @removed_id = removed_id
      @excluded_ids = Array(visible_ids) | [removed_id]
      @options = options
      @search = search
    end

    def call
      Results::Query.call(@base_scope, @options, search: @search)
                    .where.not(id: @excluded_ids)
                    .first
    end
  end
end
