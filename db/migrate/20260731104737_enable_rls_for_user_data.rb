class EnableRlsForUserData < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION current_user_id()
      RETURNS bigint AS $$
        SELECT NULLIF(current_setting('app.current_user_id', true), '')::bigint;
      $$ LANGUAGE sql STABLE;
    SQL

    execute "ALTER TABLE searches ENABLE ROW LEVEL SECURITY;"
    execute <<~SQL
      CREATE POLICY search_user_isolation ON searches FOR ALL
      USING (user_id = current_user_id())
      WITH CHECK (user_id = current_user_id());
    SQL

    execute "ALTER TABLE results ENABLE ROW LEVEL SECURITY;"
    execute <<~SQL
      CREATE POLICY result_user_isolation ON results FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM searches
          WHERE searches.id = results.search_id
            AND searches.user_id = current_user_id()
        )
      );
    SQL

    execute "ALTER TABLE prompts ENABLE ROW LEVEL SECURITY;"
    execute <<~SQL
      CREATE POLICY prompt_user_isolation ON prompts FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM searches
          WHERE searches.id = prompts.search_id
            AND searches.user_id = current_user_id()
        )
      );
    SQL

    %i[searches results prompts].each do |table|
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;"
    end
  end

  def down
    %i[prompts results searches].each do |table|
      execute "DROP POLICY IF EXISTS #{table.to_s.singularize}_user_isolation ON #{table};"
      execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;"
    end

    execute "DROP FUNCTION IF EXISTS current_user_id();"
  end
end