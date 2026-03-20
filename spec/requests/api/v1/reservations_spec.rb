require 'rails_helper'

RSpec.describe "Api::V1::Reservations", type: :request do
  let(:room) { create(:room) }
  let(:user) { create(:user, :admin) } # Use admin to avoid capacity limits

  describe "GET /api/v1/reservations" do
    it "returns all reservations" do
      Timecop.freeze(Time.zone.local(2026, 3, 24, 10, 0, 0)) do
        rooms = create_list(:room, 3)
        users = create_list(:user, 3)
        create(:reservation, room: rooms[0], user: users[0])
        create(:reservation, room: rooms[1], user: users[1])
        create(:reservation, room: rooms[2], user: users[2])
      end
      get "/api/v1/reservations"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(3)
    end
  end

  describe "GET /api/v1/reservations/:id" do
    it "returns the reservation" do
      Timecop.freeze(Time.zone.local(2026, 3, 24, 10, 0, 0)) do
        reservation = create(:reservation, room: room, user: user)
        get "/api/v1/reservations/#{reservation.id}"
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["id"]).to eq(reservation.id)
      end
    end
  end

  describe "POST /api/v1/reservations" do
    let(:valid_attributes) do
      {
        title: "Team meeting",
        starts_at: Time.zone.local(2026, 3, 24, 10, 0, 0),
        ends_at: Time.zone.local(2026, 3, 24, 11, 0, 0),
        room_id: room.id,
        user_id: user.id
      }
    end

    it "creates a reservation" do
      Timecop.freeze(Time.zone.local(2026, 3, 20, 9, 0, 0)) do
        expect {
          post "/api/v1/reservations", params: { reservation: valid_attributes }
        }.to change(Reservation, :count).by(1)
        expect(response).to have_http_status(:created)
      end
    end

    it "creates recurring reservations" do
      Timecop.freeze(Time.zone.local(2026, 3, 20, 9, 0, 0)) do
        expect {
          post "/api/v1/reservations", params: { reservation: valid_attributes.merge(recurring: 'daily', recurring_until: '2026-03-26') }
        }.to change(Reservation, :count).by(3)
        expect(response).to have_http_status(:created)
      end
    end

    it "returns errors for invalid data" do
      Timecop.freeze(Time.zone.local(2026, 3, 20, 9, 0, 0)) do
        post "/api/v1/reservations", params: { reservation: valid_attributes.merge(starts_at: nil) }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["errors"]).to be_present
      end
    end
  end

  describe "PATCH /api/v1/reservations/:id/cancel" do
    it "cancels the reservation if allowed" do
      Timecop.freeze(Time.zone.local(2026, 3, 20, 9, 0, 0)) do
        reservation = create(:reservation, room: room, user: user, starts_at: Time.zone.local(2026, 3, 24, 10, 0, 0), ends_at: Time.zone.local(2026, 3, 24, 11, 0, 0))
        patch "/api/v1/reservations/#{reservation.id}/cancel"
        expect(response).to have_http_status(:ok)
        expect(reservation.reload.cancelled_at).to be_present
      end
    end

    it "returns error if cancellation not allowed" do
      Timecop.freeze(Time.zone.local(2026, 3, 24, 10, 30, 0)) do
        reservation = create(:reservation, room: room, user: user, starts_at: Time.zone.local(2026, 3, 24, 11, 0, 0), ends_at: Time.zone.local(2026, 3, 24, 12, 0, 0))
        patch "/api/v1/reservations/#{reservation.id}/cancel"
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["errors"]).to include("Reservation cannot be cancelled at this time")
      end
    end
  end
end