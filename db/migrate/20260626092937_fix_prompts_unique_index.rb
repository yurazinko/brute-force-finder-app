class FixPromptsUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :prompts, column: [:target_id, :full_query_text]
    add_index :prompts, [:search_id, :target_id, :full_query_text], unique: true, name: "index_prompts_on_search_target_and_query"
  end
end
