class AddNullFalseToPromptsFullQueryText < ActiveRecord::Migration[8.1]
  def change
    change_column_null :prompts, :full_query_text, false
  end
end
