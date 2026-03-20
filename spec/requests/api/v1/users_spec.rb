require 'rails_helper'

RSpec.describe "Api::V1::Users", type: :request do
  describe "GET /api/v1/users" do
    it "returns all users" do
      create_list(:user, 3)
      get "/api/v1/users"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(3)
    end
  end

  describe "GET /api/v1/users/:id" do
    it "returns the user" do
      user = create(:user)
      get "/api/v1/users/#{user.id}"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(user.id)
    end
  end

  describe "POST /api/v1/users" do
    let(:valid_attributes) { { name: "John Doe", email: "john@example.com", department: "Engineering" } }

    it "creates a user" do
      expect {
        post "/api/v1/users", params: { user: valid_attributes }
      }.to change(User, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "returns errors for invalid data" do
      post "/api/v1/users", params: { user: { name: nil } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end
  end
end