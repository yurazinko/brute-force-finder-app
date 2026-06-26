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

ActiveRecord::Schema[8.1].define(version: 2026_06_26_183215) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "prompts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "full_query_text", null: false
    t.bigint "search_id", null: false
    t.string "status", default: "pending"
    t.bigint "target_id", null: false
    t.datetime "updated_at", null: false
    t.index ["search_id", "target_id", "full_query_text"], name: "index_prompts_on_search_target_and_query", unique: true
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
    t.index ["search_id", "status"], name: "index_results_on_search_id_and_status"
    t.index ["search_id", "url_hash"], name: "index_results_on_search_id_and_url_hash", unique: true
    t.index ["search_id"], name: "index_results_on_search_id"
    t.index ["url_hash"], name: "index_results_on_url_hash"
  end

  create_table "searches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "query_conditions"
    t.string "status", default: "pending"
    t.string "time_frame"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "targets", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.string "domain"
    t.boolean "is_active", default: true
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_targets_on_category_id"
    t.index ["domain"], name: "index_targets_on_domain", unique: true
  end

  add_foreign_key "prompts", "searches"
  add_foreign_key "prompts", "targets"
  add_foreign_key "results", "searches"
  add_foreign_key "targets", "categories"
end
