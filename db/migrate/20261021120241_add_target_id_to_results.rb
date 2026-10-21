class AddTargetIdToResults < ActiveRecord::Migration[8.1]
  def change
    add_reference :results, :target, foreign_key: true, null: true
    add_index :results, [:search_id, :target_id]
  end
end
