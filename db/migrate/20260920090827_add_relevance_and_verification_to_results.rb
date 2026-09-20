class AddRelevanceAndVerificationToResults < ActiveRecord::Migration[8.1]
  def change
    add_column :results, :relevance_score, :integer, default: 0, null: false
    add_column :results, :matched_keywords, :jsonb, default: [], null: false
    add_column :results, :verification_status, :string, default: "pending", null: false

    add_index :results, :relevance_score
    add_index :results, %i[search_id relevance_score]
    add_index :results, :verification_status
  end
end
