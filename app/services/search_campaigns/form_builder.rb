# frozen_string_literal: true

module SearchCampaigns
  class FormBuilder
    FormState = Struct.new(:search, :back_path, :back_label, :alert, keyword_init: true)

    def initialize(user:, params:, root_path:, list_path:)
      @user = user
      @params = params
      @root_path = root_path
      @list_path = list_path
    end

    def call
      if params[:clone_from].present?
        build_from_clone
      elsif params[:quick_search_token].present?
        build_from_quick_search
      else
        default_state
      end
    end

    private

    attr_reader :user, :params, :root_path, :list_path

    def default_state
      FormState.new(
        search: Search.new,
        back_path: list_path,
        back_label: "Back to List",
        alert: nil
      )
    end

    def build_from_clone
      donor = user.searches.find_by(id: params[:clone_from])
      search = donor ? clone_record(donor) : Search.new

      FormState.new(
        search: search,
        back_path: list_path,
        back_label: "Back to List",
        alert: nil
      )
    end

    def build_from_quick_search
      quick_search = QuickSearch::Store.fetch(params[:quick_search_token])
      return expired_quick_search_state unless quick_search

      query = quick_search.fetch("query")
      token = quick_search.fetch("token", params[:quick_search_token])

      FormState.new(
        search: build_search_from_query(query),
        back_path: root_path.call(quick_search: token),
        back_label: "Back to Quick Search Results",
        alert: nil
      )
    end

    def expired_quick_search_state
      FormState.new(
        search: Search.new,
        back_path: list_path,
        back_label: "Back to List",
        alert: "This quick search session has expired. Run the search again."
      )
    end

    def build_search_from_query(query)
      user.searches.build(
        title: "Search for #{query}".truncate(120),
        query_conditions: QuickSearch::QueryFormatter.call(query),
        relevance_mode: Search::DEFAULT_RELEVANCE_MODE
      )
    end

    def clone_record(donor)
      user.searches.build(
        title: "#{donor.title} (Copy)",
        query_conditions: donor.query_conditions,
        time_frame: donor.time_frame,
        show_acknowledged: donor.show_acknowledged,
        relevance_mode: donor.relevance_mode,
        target_ids: donor.target_ids
      )
    end
  end
end
