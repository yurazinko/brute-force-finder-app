# frozen_string_literal: true

module Results
  class Index
    include FilterableContext

    attr_reader :base_scope, :options, :search

    def self.call(base_scope, options = {}, search = nil)
      new(base_scope, options, search).call
    end

    def initialize(base_scope, options = {}, search = nil)
      @base_scope = base_scope
      @options = options.to_h.symbolize_keys
      @search = search
    end

    def call
      apply_filters(base_scope).order(sorting_order)
    end

    private

    def apply_filters(scope)
      scope = scope.by_time_frame(options[:time_frame])
      scope = scope.search_by_keyword(options[:keyword])
      scope = filter_by_status(scope)
      filter_by_relevance(scope)
    end

    def filter_by_status(scope)
      status = options[:status].to_s
      if %w[garbage interesting watched].include?(status)
        scope.where(status: status)
      else
        search_ack = search.respond_to?(:show_acknowledged) ? cast_boolean(search.show_acknowledged) : false
        scope.where(
          status: "unread",
          acknowledged: unread_acknowledged_conditions(options, search_show_acknowledged: search_ack)
        )
      end
    end

    def filter_by_relevance(scope)
      if cast_boolean(options[:show_less_relevant])
        scope.where("results.relevance_score <= 0")
      else
        scope.where("results.relevance_score > 0")
      end
    end

    def sorting_order
      {
        "created_asc" => { created_at: :asc, id: :asc },
        "created_desc" => { created_at: :desc, id: :desc },
        "updated_desc" => { updated_at: :desc, id: :desc },
        "updated_asc" => { updated_at: :asc, id: :asc }
      }.fetch(options[:sort].to_s, { relevance_score: :desc, created_at: :desc, id: :desc })
    end
  end
end
