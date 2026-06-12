class CreateSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :searches do |t|
      t.string :title
      t.text :query_conditions
      t.string :status, default: "pending"

      t.timestamps
    end
  end
end
