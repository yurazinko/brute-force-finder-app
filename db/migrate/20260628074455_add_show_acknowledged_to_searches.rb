class AddShowAcknowledgedToSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :searches, :show_acknowledged, :boolean, default: false, null: false
  end
end
