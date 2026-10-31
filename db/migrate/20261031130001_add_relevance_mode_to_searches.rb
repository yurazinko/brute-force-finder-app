class AddRelevanceModeToSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :searches, :relevance_mode, :string, default: "strict", null: false
  end
end
