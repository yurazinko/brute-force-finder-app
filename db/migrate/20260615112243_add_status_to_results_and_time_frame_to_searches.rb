class AddStatusToResultsAndTimeFrameToSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :searches, :time_frame, :string
    add_column :results, :status, :string, default: "unread", null: false

     add_index :results, [:search_id, :status]
  end
end