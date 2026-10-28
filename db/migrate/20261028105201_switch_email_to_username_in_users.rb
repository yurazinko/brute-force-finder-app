class SwitchEmailToUsernameInUsers < ActiveRecord::Migration[8.1]
  def change

    add_column :users, :username, :string, null: false, default: ""

    reversible do |dir|
      dir.up do
        execute("UPDATE users SET username = email WHERE username = '' OR username IS NULL")
      end
    end

    remove_index :users, :email if index_exists?(:users, :email)
    remove_column :users, :email, :string

    add_index :users, :username, unique: true
  end
end
