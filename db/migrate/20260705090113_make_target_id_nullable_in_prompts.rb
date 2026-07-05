class MakeTargetIdNullableInPrompts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :prompts, :target_id, true

    remove_index :prompts, name: :index_prompts_on_search_target_and_query

    add_index :prompts, [:search_id, :target_id, :full_query_text],
              unique: true,
              where: "target_id IS NOT NULL",
              name: "index_prompts_on_search_target_and_query"

    add_index :prompts, [:search_id, :full_query_text],
          unique: true,
          where: "target_id IS NULL",
          name: "index_global_prompts_on_search_and_query"
  end
end
