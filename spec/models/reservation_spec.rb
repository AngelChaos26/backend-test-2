require 'rails_helper'

RSpec.describe Reservation, type: :model do
  let(:room) { create(:room) }
  let(:user) { create(:user) }

  describe 'validations' do
    it 'is valid with valid attributes' do
      reservation = build(:reservation, room: room, user: user)
      expect(reservation).to be_valid
    end

    it 'is invalid without a title' do
      reservation = build(:reservation, title: nil)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:title]).to include("can't be blank")
    end

    it 'is invalid without starts_at' do
      reservation = build(:reservation, starts_at: nil)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:starts_at]).to include("can't be blank")
    end

    it 'is invalid without ends_at' do
      reservation = build(:reservation, ends_at: nil)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:ends_at]).to include("can't be blank")
    end

    it 'is invalid if ends_at is not after starts_at' do
      time = Time.current
      reservation = build(:reservation, starts_at: time, ends_at: time)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:ends_at]).to include("must be after starts_at")
    end

    it 'is invalid if ends_at is before starts_at' do
      reservation = build(:reservation, starts_at: Time.current + 1.hour, ends_at: Time.current)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:ends_at]).to include("must be after starts_at")
    end

    it 'is invalid if longer than 4 hours' do
      reservation = build(:reservation, :too_long, room: room, user: user)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:base]).to include("Reservation cannot be longer than 4 hours")
    end

    it 'is invalid if starts_at is in the past' do
      reservation = build(:reservation, room: room, user: user, starts_at: 1.hour.ago, ends_at: 2.hours.from_now)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:starts_at]).to include("must be in the future")
    end

    describe 'capacity restriction' do
      let(:small_room) { create(:room, capacity: 5) }
      let(:large_room) { create(:room, capacity: 15) }
      let(:limited_user) { create(:user, :limited) } # max_capacity_allowed: 5
      let(:admin_user) { create(:user, :admin) }

      it 'is valid if user is admin' do
        reservation = build(:reservation, room: large_room, user: admin_user)
        expect(reservation).to be_valid
      end

      it 'is valid if room capacity is within user limit' do
        reservation = build(:reservation, room: small_room, user: limited_user)
        expect(reservation).to be_valid
      end

      it 'is invalid if room capacity exceeds user limit' do
        reservation = build(:reservation, room: large_room, user: limited_user)
        expect(reservation).not_to be_valid
        expect(reservation.errors[:base]).to include("User cannot book rooms with capacity greater than their allowed limit")
      end
    end

    describe 'active reservation limit' do
      let(:user_with_limit) { create(:user) }
      let(:admin_user) { create(:user, :admin) }

      before do
        3.times { create(:reservation, user: user_with_limit) }
      end

      it 'is valid for admin users' do
        reservation = build(:reservation, user: admin_user)
        expect(reservation).to be_valid
      end

      it 'is invalid if user has 3 or more active reservations' do
        reservation = build(:reservation, user: user_with_limit)
        expect(reservation).not_to be_valid
        expect(reservation.errors[:base]).to include("User cannot have more than 3 active reservations")
      end

      it 'is valid if user has less than 3 active reservations' do
        user_with_few = create(:user)
        reservation = build(:reservation, user: user_with_few)
        2.times { create(:reservation, user: user_with_few) }
        expect(reservation).to be_valid
      end
    end

    describe '#can_cancel?' do
      # Garantee consistent time for testing can_cancel? logic
      Timecop.freeze(Time.zone.now.next_occurring(:monday).change(hour: 10, min: 0)) do
        it 'returns true if more than 60 minutes until start' do
          reservation = build(:reservation, starts_at: 2.hours.from_now)
          expect(reservation.can_cancel?).to be true
        end

        it 'returns false if less than 60 minutes until start' do
          reservation = build(:reservation, starts_at: 30.minutes.from_now)
          expect(reservation.can_cancel?).to be false
        end

        it 'returns false if already cancelled' do
          reservation = build(:reservation, :cancelled, starts_at: 2.hours.from_now)
          expect(reservation.can_cancel?).to be false
        end
      end
    end

    describe 'room availability' do
      let!(:existing_reservation) { create(:reservation, room: room, user: user) }

      it 'is valid if no overlap' do
        new_reservation = build(:reservation, room: room, user: user, starts_at: existing_reservation.ends_at, ends_at: existing_reservation.ends_at + 1.hour)
        expect(new_reservation).to be_valid
      end

      it 'is invalid if starts during existing reservation' do
        new_reservation = build(:reservation, room: room, user: user, starts_at: existing_reservation.starts_at + 30.minutes, ends_at: existing_reservation.ends_at + 30.minutes)
        expect(new_reservation).not_to be_valid
        expect(new_reservation.errors[:base]).to include("Room is already reserved during this time period")
      end

      it 'is invalid if completely overlaps existing reservation' do
        new_reservation = build(:reservation, room: room, user: user, starts_at: existing_reservation.starts_at - 30.minutes, ends_at: existing_reservation.ends_at + 30.minutes)
        expect(new_reservation).not_to be_valid
        expect(new_reservation.errors[:base]).to include("Room is already reserved during this time period")
      end

      it 'is valid if existing reservation is cancelled' do
        existing_reservation.update(cancelled_at: Time.current)
        new_reservation = build(:reservation, room: room, user: user, starts_at: existing_reservation.starts_at, ends_at: existing_reservation.ends_at)
        expect(new_reservation).to be_valid
      end

      it 'is valid for different room' do
        other_room = create(:room)
        new_reservation = build(:reservation, room: other_room, user: user, starts_at: existing_reservation.starts_at, ends_at: existing_reservation.ends_at)
        expect(new_reservation).to be_valid
      end

      it 'allows updating the same reservation' do
        expect(existing_reservation.update(title: "Updated title")).to be true
      end
    end

    describe 'recurring reservations' do
      it 'creates all daily occurrences until recurring_until when valid' do
        start_time = Time.zone.now.next_occurring(:monday).change(hour: 10)
        start_time += 1.week if start_time <= Time.zone.now

        reservation = Reservation.create_with_recurrence!(
          room: room,
          user: user,
          title: 'Team meeting',
          starts_at: start_time,
          ends_at: start_time + 1.hour,
          recurring: 'daily',
          recurring_until: (start_time + 2.days).to_date
        )

        expect(reservation).to be_persisted
        expect(Reservation.where(room: room, user: user).count).to eq(3)
      end

      it 'rolls back all when an occurrence overlaps (BR1) in the series' do
        initial = create(:reservation, room: room, user: user, starts_at: Time.zone.now.next_occurring(:monday).change(hour: 10), ends_at: Time.zone.now.next_occurring(:monday).change(hour: 11))

        expect do
          Reservation.create_with_recurrence!(
            room: room,
            user: user,
            title: 'Recurring',
            starts_at: initial.starts_at,
            ends_at: initial.ends_at,
            recurring: 'weekly',
            recurring_until: (initial.starts_at + 2.weeks).to_date
          )
        end.to raise_error(ActiveRecord::RecordInvalid)

        expect(Reservation.where(room: room, user: user).count).to eq(1)
      end

      it 'does not create any recurrence if user active limit is exceeded by full series (BR5)' do
        2.times do |i|
          create(:reservation, room: room, user: user, starts_at: Time.zone.now.next_occurring(:monday).change(hour: 9) + i.days, ends_at: Time.zone.now.next_occurring(:monday).change(hour: 10) + i.days)
        end

        expect do
          Reservation.create_with_recurrence!(
            room: room,
            user: user,
            title: 'Recurring limit',
            starts_at: Time.zone.now.next_occurring(:monday).change(hour: 11),
            ends_at: Time.zone.now.next_occurring(:monday).change(hour: 12),
            recurring: 'daily',
            recurring_until: (Time.zone.now.next_occurring(:monday).to_date + 2.days)
          )
        end.to raise_error(ActiveRecord::RecordInvalid, /User cannot have more than 3 active reservations/)

        expect(Reservation.where(room: room, user: user).count).to eq(2)
      end

      it 'raises if recurring_until is missing for recurring reservations' do
        expect do
          Reservation.create_with_recurrence!(
            room: room,
            user: user,
            title: 'Failing',
            starts_at: Time.zone.now.next_occurring(:monday).change(hour: 10),
            ends_at: Time.zone.now.next_occurring(:monday).change(hour: 11),
            recurring: 'daily',
            recurring_until: nil
          )
        end.to raise_error(ArgumentError, /recurring_until must be present/)
      end
    end

    describe 'business hours' do
      it 'is valid during business hours on weekday' do
        monday = Time.zone.now.next_occurring(:monday).change(hour: 10)
        monday += 1.week if monday <= Time.zone.now
        reservation = build(:reservation, room: room, user: user, starts_at: monday, ends_at: monday + 1.hour)
        expect(reservation).to be_valid
      end

      it 'is invalid on Saturday' do
        saturday = Time.zone.now.next_occurring(:saturday).change(hour: 10)
        saturday += 1.week if saturday <= Time.zone.now
        reservation = build(:reservation, room: room, user: user, starts_at: saturday, ends_at: saturday + 1.hour)
        expect(reservation).not_to be_valid
        expect(reservation.errors[:base]).to include("Reservations can only be made Monday through Friday")
      end

      it 'is invalid on Sunday' do
        sunday = Time.zone.now.next_occurring(:sunday).change(hour: 10)
        sunday += 1.week if sunday <= Time.zone.now
        reservation = build(:reservation, room: room, user: user, starts_at: sunday, ends_at: sunday + 1.hour)
        expect(reservation).not_to be_valid
        expect(reservation.errors[:base]).to include("Reservations can only be made Monday through Friday")
      end

      it 'is invalid before 9 AM' do
        monday = Time.zone.now.next_occurring(:monday).change(hour: 8)
        monday += 1.week if monday <= Time.zone.now
        reservation = build(:reservation, room: room, user: user, starts_at: monday, ends_at: monday + 1.hour)
        expect(reservation).not_to be_valid
        expect(reservation.errors[:base]).to include("Reservations can only be between 9:00 AM and 6:00 PM")
      end

      it 'is invalid after 6 PM' do
        monday = Time.zone.now.next_occurring(:monday).change(hour: 18)
        monday += 1.week if monday <= Time.zone.now
        reservation = build(:reservation, room: room, user: user, starts_at: monday, ends_at: monday + 1.hour)
        expect(reservation).not_to be_valid
        expect(reservation.errors[:base]).to include("Reservations can only be between 9:00 AM and 6:00 PM")
      end

      it 'is valid at exactly 6 PM' do
        monday = Time.zone.now.next_occurring(:monday).change(hour: 17)
        monday += 1.week if monday <= Time.zone.now
        reservation = build(:reservation, room: room, user: user, starts_at: monday, ends_at: monday + 1.hour)
        expect(reservation).to be_valid
      end

      it 'is invalid if ends after 6 PM' do
        monday = Time.zone.now.next_occurring(:monday).change(hour: 17)
        monday += 1.week if monday <= Time.zone.now
        reservation = build(:reservation, room: room, user: user, starts_at: monday, ends_at: monday + 2.hours)
        expect(reservation).not_to be_valid
        expect(reservation.errors[:base]).to include("Reservations can only be between 9:00 AM and 6:00 PM")
      end
    end
  end
end
