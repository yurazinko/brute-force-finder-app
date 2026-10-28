# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  encrypted_password     :string           default(""), not null
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  username               :string           default(""), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_username              (username) UNIQUE
#
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :rememberable

  has_one_attached :data_export

  has_many :searches, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :targets, through: :categories
  has_many :results, through: :searches

  validates :username, presence: true, uniqueness: true, length: { minimum: 2, maximum: 30 }
  validates :password, presence: true, length: { minimum: 6 }, confirmation: true, on: :create
end
