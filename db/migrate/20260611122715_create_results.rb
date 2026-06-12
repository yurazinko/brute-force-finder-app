class CreateResults < ActiveRecord::Migration[8.1]
  def change
    create_table :results do |t|
      t.references :search, null: false, foreign_key: true
      t.string :url, null: false
      t.string :url_hash, null: false
      t.string :title
      t.text :content
      t.datetime :viewed_at

      t.timestamps
    end

    add_index :results, [:search_id, :url_hash], unique: true
  end
end
