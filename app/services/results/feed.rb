# frozen_string_literal: true

module Results
  class Feed
    Result = Struct.new(:record, :has_more?)

    def self.next_after(scope:, visible_ids:, params:, limit: 1)
      new(scope, visible_ids, params).next_records(limit)
    end

    def initialize(scope, visible_ids, params)
      @base_scope = scope
      @visible_ids = Array(visible_ids).map(&:to_i)
      @params = params
    end

    def next_records(limit)
      filtered_scope = ResultsFilterScope.call(@base_scope, filter_options)

      feed_scope = filtered_scope.where.not(id: @visible_ids)

      records = feed_scope.limit(limit + 1).to_a
      has_more = records.size > limit

      Result.new(records.first, has_more)
    end

    private

    def filter_options
      {
        status: @params[:status],
        time_frame: @params[:d],
        keyword: @params[:q],
        sort: @params[:sort],
        show_acknowledged: @params[:show_acknowledged]
      }.compact
    end
  end
end
