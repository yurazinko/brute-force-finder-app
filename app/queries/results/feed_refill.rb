# frozen_string_literal: true

module Results
  class FeedRefill
    DEFAULT_FEED_SIZE = 20

    def self.next_card(base_scope:, removed_id:, current_dom_count:, options:, search: nil)
      new(
        base_scope: base_scope,
        removed_id: removed_id,
        current_dom_count: current_dom_count,
        options: options,
        search: search
      ).call
    end

    def initialize(base_scope:, removed_id:, current_dom_count:, options:, search: nil)
      @base_scope = base_scope
      @removed_id = removed_id
      @current_dom_count = current_dom_count
      @options = options
      @search = search
    end

    def call
      dom_count = @current_dom_count.to_i
      dom_count = DEFAULT_FEED_SIZE if dom_count <= 0

      Results::Query.call(@base_scope, @options, search: @search)
                    .where.not(id: @removed_id)
                    .offset([dom_count - 1, 0].max)
                    .first
    end
  end
end
