# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

job_category = Category.create!(name: "ATS / Job Boards")
job_category.targets.create!(name: "Lever", domain: "lever.co")
job_category.targets.create!(name: "Greenhouse", domain: "greenhouse.io")

estate_category = Category.create!(name: "Real Estate")
estate_category.targets.create!(name: "OLX", domain: "olx.ua/d/nedvizhimost")
