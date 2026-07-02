class AddAllowQueryStringsToTargets < ActiveRecord::Migration[8.1]
  def change
    add_column :targets, :allow_query_strings, :boolean, default: false, null: false
  end
end
