class CreateResults < ActiveRecord::Migration[8.1]
  def change
    create_table :results do |t|
      t.references :search, null: false, foreign_key: true
      t.string :url
      t.string :title
      t.text :content
      t.datetime :viewed_at

      t.timestamps
    end
  end
end
