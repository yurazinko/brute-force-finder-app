class RemoveUniqueIndexFromTargetsDomain < ActiveRecord::Migration[8.1]
  def change
    remove_index :targets, column: :domain, unique: true
    add_index :targets, :domain
  end
end
