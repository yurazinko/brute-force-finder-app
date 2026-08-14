# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_13_112403) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id", "name"], name: "index_categories_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "prompts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "full_query_text", null: false
    t.bigint "search_id", null: false
    t.string "status", default: "pending"
    t.bigint "target_id"
    t.datetime "updated_at", null: false
    t.index ["search_id", "full_query_text"], name: "index_global_prompts_on_search_and_query", unique: true, where: "(target_id IS NULL)"
    t.index ["search_id", "target_id", "full_query_text"], name: "index_prompts_on_search_target_and_query", unique: true, where: "(target_id IS NOT NULL)"
    t.index ["search_id"], name: "index_prompts_on_search_id"
    t.index ["target_id"], name: "index_prompts_on_target_id"
  end

  create_table "results", force: :cascade do |t|
    t.boolean "acknowledged", default: false, null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "search_id", null: false
    t.string "status", default: "unread", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.string "url_hash", null: false
    t.datetime "viewed_at"
    t.index ["content"], name: "idx_results_content_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["search_id", "status", "acknowledged"], name: "idx_results_analytics"
    t.index ["search_id", "status"], name: "index_results_on_search_id_and_status"
    t.index ["search_id", "url_hash"], name: "index_results_on_search_id_and_url_hash", unique: true
    t.index ["search_id"], name: "index_results_on_search_id"
    t.index ["title"], name: "idx_results_title_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["url"], name: "idx_results_url_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["url_hash"], name: "index_results_on_url_hash"
  end

  create_table "searches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "query_conditions"
    t.boolean "show_acknowledged", default: false, null: false
    t.string "status", default: "pending"
    t.string "time_frame"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_searches_on_user_id"
  end

  create_table "targets", force: :cascade do |t|
    t.boolean "allow_query_strings", default: false, null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.string "domain"
    t.boolean "is_active", default: true
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_targets_on_category_id"
    t.index ["domain"], name: "index_targets_on_domain", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "categories", "users"
  add_foreign_key "prompts", "searches"
  add_foreign_key "prompts", "targets"
  add_foreign_key "results", "searches"
  add_foreign_key "searches", "users"
  add_foreign_key "targets", "categories"
end
