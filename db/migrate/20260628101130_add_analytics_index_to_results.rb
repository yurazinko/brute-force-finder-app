class AddAnalyticsIndexToResults < ActiveRecord::Migration[8.1]
  def change
    add_index :results, [:search_id, :status, :acknowledged], name: "idx_results_analytics"
  end
end
