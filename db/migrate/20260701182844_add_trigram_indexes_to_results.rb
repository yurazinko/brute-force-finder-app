class AddTrigramIndexesToResults < ActiveRecord::Migration[8.1]
  def change
    enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')

    add_index :results, :title,   using: :gin, opclass: :gin_trgm_ops, name: 'idx_results_title_trgm'
    add_index :results, :url,     using: :gin, opclass: :gin_trgm_ops, name: 'idx_results_url_trgm'
    add_index :results, :content, using: :gin, opclass: :gin_trgm_ops, name: 'idx_results_content_trgm'
  end
end
