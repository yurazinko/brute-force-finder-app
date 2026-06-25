class AddAcknowledgedToResults < ActiveRecord::Migration[8.1]
  def change
    add_column :results, :acknowledged, :boolean, default: false, null: false
    add_index :results, :url_hash
  end
end
