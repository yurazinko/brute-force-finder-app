class AddUserToSearchesAndCategories < ActiveRecord::Migration[8.1]
  def change
    add_reference :searches, :user, foreign_key: true
    add_reference :categories, :user, foreign_key: true
  end
end
