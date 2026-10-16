# frozen_string_literal: true

module Database
  class DataExportService
    attr_reader :user, :requested_tables

    ALL_TABLES = %w[categories targets target_patterns searches prompts results].freeze

    def initialize(user, tables: nil)
      @user = user
      @requested_tables = tables.present? ? (tables & ALL_TABLES) : ALL_TABLES
    end

    def call(&)
      datasets = scoped_datasets
      json_string = generate_export_json(datasets, &)
      attach_export_file(json_string)
      notify_completion(&) if block_given?

      true
    end

    private

    def generate_export_json(datasets, &)
      export_data = {}
      total_steps = datasets.size

      datasets.each_with_index do |(table_name, scope), index|
        notify_progress(index, total_steps, table_name, &) if block_given?
        export_data[table_name] = scope.as_json
      end

      JSON.pretty_generate(export_data)
    end

    def attach_export_file(json_string)
      filename = "export-user-#{user.id}-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.json"

      user.data_export.attach(
        io: StringIO.new(json_string),
        filename: filename,
        content_type: "application/json"
      )
    end

    def notify_completion(&)
      download_url = Rails.application.routes.url_helpers.rails_blob_path(
        user.data_export.blob,
        expires_in: 1.hour,
        disposition: "attachment",
        only_path: true
      )

      html = "Done! Click <a href='#{download_url}' download class='text-breeze-accent " \
             "underline font-semibold'>here</a> to download (link expires in 1 hour)."
      yield(100, html)
    end

    def scoped_datasets
      user_categories = user.categories
      user_searches   = user.searches

      all_datasets = {
        "categories" => user_categories,
        "targets" => Target.where(category_id: user_categories.select(:id)),
        "searches" => user_searches,
        "prompts" => Prompt.where(search_id: user_searches.select(:id)),
        "results" => Result.where(search_id: user_searches.select(:id))
      }

      all_datasets.slice(*requested_tables).to_a
    end

    def notify_progress(index, total_steps, table_name, &)
      progress = ((index.to_f / total_steps) * 100).to_i
      yield(progress, "Exporting #{table_name}...")
    end
  end
end
