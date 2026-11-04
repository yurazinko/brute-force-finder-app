class EnableRlsForRemainingUserData < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE categories ENABLE ROW LEVEL SECURITY;"
    execute <<~SQL
      CREATE POLICY category_user_isolation ON categories FOR ALL
      USING (user_id = current_user_id())
      WITH CHECK (user_id = current_user_id());
    SQL

    execute "ALTER TABLE targets ENABLE ROW LEVEL SECURITY;"
    execute <<~SQL
      CREATE POLICY target_user_isolation ON targets FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM categories
          WHERE categories.id = targets.category_id
            AND categories.user_id = current_user_id()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM categories
          WHERE categories.id = targets.category_id
            AND categories.user_id = current_user_id()
        )
      );
    SQL

    execute "ALTER TABLE target_patterns ENABLE ROW LEVEL SECURITY;"
    execute <<~SQL
      CREATE POLICY target_pattern_user_isolation ON target_patterns FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM targets
          JOIN categories ON categories.id = targets.category_id
          WHERE targets.id = target_patterns.target_id
            AND categories.user_id = current_user_id()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM targets
          JOIN categories ON categories.id = targets.category_id
          WHERE targets.id = target_patterns.target_id
            AND categories.user_id = current_user_id()
        )
      );
    SQL

    %i[categories targets target_patterns].each do |table|
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;"
    end
  end

  def down
    %i[target_patterns targets categories].each do |table|
      policy_name = case table
                    when :target_patterns then "target_pattern_user_isolation"
                    when :targets then "target_user_isolation"
                    when :categories then "category_user_isolation"
                    end
      execute "DROP POLICY IF EXISTS #{policy_name} ON #{table};"
      execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;"
    end
  end
end
