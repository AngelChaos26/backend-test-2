class User < ApplicationRecord
  has_many :reservations

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  scope :active_reservations, -> { reservations.where(cancelled_at: nil) }
end
