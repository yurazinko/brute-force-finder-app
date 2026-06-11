class CreatePrompts < ActiveRecord::Migration[8.1]
  def change
    create_table :prompts do |t|
      t.references :search, null: false, foreign_key: true
      t.references :target, null: false, foreign_key: true
      t.string :full_query_text
      t.string :status
      t.text :error_message

      t.timestamps
    end

    add_index :prompts, [:target_id, :full_query_text], unique: true
  end
end
