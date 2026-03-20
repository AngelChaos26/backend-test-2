class RoomAvailabilityValidator < ActiveModel::Validator
  def validate(record)
    return if record.room_id.blank? || record.starts_at.blank? || record.ends_at.blank?

    overlapping_reservations = Reservation.where(room_id: record.room_id, cancelled_at: nil)
                                         .where.not(id: record.id)
                                         .where("starts_at < ? AND ? < ends_at", record.ends_at, record.starts_at)

    if overlapping_reservations.exists?
      record.errors.add(:base, "Room is already reserved during this time period")
    end

    check_for_maximum_duration(record)
    check_for_business_hours(record)
    restriction_by_user(record)
  end

  def check_for_maximum_duration(record)
    return if record.starts_at.blank? || record.ends_at.blank?

    duration_in_minutes = ((record.ends_at - record.starts_at) / 1.minute).round(2)
    if duration_in_minutes > 240
      record.errors.add(:base, "Reservation cannot be longer than 4 hours")
    end
  end

  def check_for_business_hours(record)
    return if record.starts_at.blank? || record.ends_at.blank?

    [record.starts_at, record.ends_at].each do |time|
      if time.wday == 0 || time.wday == 6
        record.errors.add(:base, "Reservations can only be made Monday through Friday")
      end
      if time.hour < 9 || time.hour > 18 || (time.hour == 18 && time.min > 0)
        record.errors.add(:base, "Reservations can only be between 9:00 AM and 6:00 PM")
      end
    end
  end

  def restriction_by_user(record)
    return if record.user.blank? || record.room.blank?

    return if record.user.is_admin?

    if record.room.capacity > record.user.max_capacity_allowed
      record.errors.add(:base, "User cannot book rooms with capacity greater than their allowed limit")
    end
  end
end