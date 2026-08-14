class FixCategoriesUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :categories, column: :name, unique: true

    add_index :categories, [:user_id, :name], unique: true
  end
end