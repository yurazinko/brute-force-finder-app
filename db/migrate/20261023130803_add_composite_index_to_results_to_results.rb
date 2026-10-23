class AddCompositeIndexToResultsToResults < ActiveRecord::Migration[8.1]
  def change
    add_index :results,
              [:search_id, :status, :acknowledged, :relevance_score],
              name: "index_results_on_search_status_ack_relevance"
  end
end
