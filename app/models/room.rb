class Room < ApplicationRecord
  validates :name, presence: true
  validates :capacity, presence: true, numericality: { greater_than: 0 }
end
