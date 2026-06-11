class CreateTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :targets do |t|
      t.references :category, null: false, foreign_key: true
      t.string :name
      t.string :domain
      t.boolean :is_active, default: true
      t.timestamps
    end

    add_index :targets, :domain, unique: true
  end
end
