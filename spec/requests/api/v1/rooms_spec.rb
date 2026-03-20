require 'rails_helper'

RSpec.describe "Api::V1::Rooms", type: :request do
  describe "GET /api/v1/rooms" do
    it "returns all rooms" do
      create_list(:room, 3)
      get "/api/v1/rooms"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(3)
    end
  end

  describe "GET /api/v1/rooms/:id" do
    it "returns the room" do
      room = create(:room)
      get "/api/v1/rooms/#{room.id}"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(room.id)
    end
  end

  describe "POST /api/v1/rooms" do
    let(:valid_attributes) { { name: "Conference Room A", capacity: 10, has_projector: true } }

    it "creates a room" do
      expect {
        post "/api/v1/rooms", params: { room: valid_attributes }
      }.to change(Room, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "returns errors for invalid data" do
      post "/api/v1/rooms", params: { room: { name: nil } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end
  end

  describe "GET /api/v1/rooms/:id/availability" do
    it "returns availability for the room" do
      room = create(:room)
      get "/api/v1/rooms/#{room.id}/availability", params: { date: "2026-03-24" }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["available"]).to eq(true)
    end
  end
end