# frozen_string_literal: true

module Database
  class DataExportService
    attr_reader :user, :output_path

    def initialize(user, output_path = nil)
      @user = user
      @output_path = output_path || default_output_path
    end

    def call(&)
      collect_records(&)

      if block_given?
        url = "/#{@output_path.basename}"
        html = "Done! Click <a href='%s' download class='text-breeze-accent " \
               "underline font-semibold'>here</a> to download."
        yield(100, format(html, url))
      end
      true
    end

    private

    def collect_records(&)
      export_data = {}
      datasets = scoped_datasets
      total_steps = datasets.size

      datasets.each_with_index do |(table_name, scope), index|
        notify_progress(index, total_steps, table_name, &) if block_given?
        export_data[table_name] = scope.as_json
      end

      @output_path.write(JSON.pretty_generate(export_data))
    end

    def scoped_datasets
      user_categories = user.categories
      user_searches   = user.searches

      [
        ["categories", user_categories],
        ["targets", Target.where(category_id: user_categories.select(:id))],
        ["searches", user_searches],
        ["prompts", Prompt.where(search_id: user_searches.select(:id))],
        ["results", Result.where(search_id: user_searches.select(:id))]
      ]
    end

    def notify_progress(index, total_steps, table_name)
      progress = ((index.to_f / total_steps) * 100).to_i
      yield(progress, "Exporting #{table_name}...")
    end

    def default_output_path
      timestamp = Time.current.strftime("%Y-%m-%d-%H%M%S")
      Rails.public_path.join("export-user-#{user.id}-#{timestamp}.json")
    end
  end
end
