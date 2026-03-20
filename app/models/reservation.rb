class Reservation < ApplicationRecord
  belongs_to :room
  belongs_to :user

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validates :room, presence: true
  validates :user, presence: true

  validate :ends_at_after_starts_at
  validate :starts_at_in_future
  validate :active_reservation_limit

  validates_with RoomAvailabilityValidator

  def self.create_with_recurrence!(attributes)
    recurring = attributes[:recurring]
    recurring_until = attributes[:recurring_until]

    return create!(attributes) if recurring.blank?

    unless %w[daily weekly].include?(recurring)
      raise ArgumentError, "recurring must be 'daily' or 'weekly'"
    end

    if recurring_until.blank?
      raise ArgumentError, 'recurring_until must be present for recurring reservations'
    end

    starts_at = attributes[:starts_at]
    ends_at = attributes[:ends_at]
    raise ArgumentError, 'starts_at and ends_at must be present' if starts_at.blank? || ends_at.blank?

    interval = recurring == 'daily' ? 1.day : 1.week
    slots = []
    current_start = starts_at
    current_end = ends_at

    while current_start.to_date <= recurring_until
      slots << [current_start, current_end]
      current_start += interval
      current_end += interval
    end

    raise ActiveRecord::RecordInvalid.new(new(attributes)) if slots.empty?

    user = User.find(attributes[:user_id]) if attributes[:user_id]
    if user && !user.is_admin?
      active_future_count = user.reservations.where(cancelled_at: nil).where('starts_at > ?', Time.current).count
      if active_future_count + slots.size > 3
        record = new(attributes)
        record.errors.add(:base, 'User cannot have more than 3 active reservations')
        raise ActiveRecord::RecordInvalid.new(record)
      end
    end

    occurrences = slots.map.with_index do |(slot_start, slot_end), index|
      occurrence_attrs = attributes.merge(starts_at: slot_start, ends_at: slot_end)
      unless index.zero?
        occurrence_attrs[:recurring] = nil
        occurrence_attrs[:recurring_until] = nil
      end
      new(occurrence_attrs)
    end

    occurrences.each(&:valid?)
    first_invalid = occurrences.find(&:invalid?)
    if first_invalid
      raise ActiveRecord::RecordInvalid.new(first_invalid)
    end

    created_record = nil
    ActiveRecord::Base.transaction do
      occurrences.each do |occurrence|
        occurrence.save!
        created_record ||= occurrence
      end
    end

    created_record
  end

  def can_cancel?
    return false if cancelled_at.present?

    starts_at > 60.minutes.from_now
  end

  private

  def ends_at_after_starts_at
    return if ends_at.blank? || starts_at.blank?

    if ends_at <= starts_at
      errors.add(:ends_at, "must be after starts_at")
    end
  end

  def starts_at_in_future
    return if starts_at.blank?

    if starts_at <= Time.current
      errors.add(:starts_at, "must be in the future")
    end
  end

  def active_reservation_limit
    return if user.blank?

    return if user.is_admin?

    active_count = user.reservations.where(cancelled_at: nil).where("starts_at > ?", Time.current).count

    if active_count >= 3
      errors.add(:base, "User cannot have more than 3 active reservations")
    end
  end
end
