# frozen_string_literal: true

module Results
  class Query
    STATUS_FILTERS = %w[garbage interesting watched].freeze
    SORTS = {
      "created_asc" => { created_at: :asc, id: :asc },
      "created_desc" => { created_at: :desc, id: :desc },
      "updated_desc" => { updated_at: :desc, id: :desc },
      "updated_asc" => { updated_at: :asc, id: :asc },
      "relevance_desc" => { relevance_score: :desc, created_at: :desc, id: :desc }
    }.freeze
    DEFAULT_SORT = "relevance_desc"

    def self.call(base_scope, options = {}, search: nil)
      new(base_scope, options, search: search).call
    end

    attr_reader :options, :search

    def initialize(base_scope, options = {}, search: nil)
      @base_scope = base_scope
      @options = options.to_h.symbolize_keys
      @search = search
    end

    def call
      filter_by_relevance(apply_status_filter(filtered_scope)).order(sorting_order)
    end

    # Common filters shared by the result feed and counter calculation.
    def filtered_scope
      scope = @base_scope
      scope = scope.by_time_frame(options[:time_frame]) if options[:time_frame].present?
      scope = scope.search_by_keyword(options[:keyword]) if options[:keyword].present?
      scope
    end

    def show_acknowledged?
      return search.show_acknowledged? if options[:show_acknowledged].nil? && search.respond_to?(:show_acknowledged?)

      ActiveModel::Type::Boolean.new.cast(options[:show_acknowledged])
    end

    def acknowledged_values
      show_acknowledged? ? [false, true] : [false]
    end

    private

    def apply_status_filter(scope)
      status = options[:status].to_s

      if STATUS_FILTERS.include?(status)
        scope.where(status: status)
      else
        scope.where(status: "unread", acknowledged: acknowledged_values)
      end
    end

    def filter_by_relevance(scope)
      return scope unless unread_status?

      if show_less_relevant?
        scope.where("results.relevance_score <= 0")
      else
        scope.where("results.relevance_score > 0")
      end
    end

    def unread_status?
      status = options[:status].to_s
      status.blank? || status == "unread"
    end

    def show_less_relevant?
      ActiveModel::Type::Boolean.new.cast(options[:show_less_relevant])
    end

    def sorting_order
      SORTS.fetch(options[:sort].to_s.presence || DEFAULT_SORT)
    end
  end
end
