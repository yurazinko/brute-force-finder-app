# frozen_string_literal: true

module Searches
  class LifecycleManager
    def self.check_completion(search)
      new(search).check_completion
    end

    def initialize(search)
      @search = search
    end

    def check_completion
      return if @search.prompts.exists?(status: %w[pending active])

      @search.update!(status: "completed")
    end
  end
end
