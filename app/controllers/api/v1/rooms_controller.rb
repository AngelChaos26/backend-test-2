module Api
  module V1
    class RoomsController < ApplicationController
      def index
        rooms = Room.all
        render json: rooms
      end

      def show
        room = Room.find(params[:id])
        render json: room
      end

      def create
        # TODO: Add admin check
        room = Room.new(room_params)
        if room.save
          render json: room, status: :created
        else
          render json: { errors: room.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def availability
        room = Room.find(params[:id])
        date = params[:date] ? Date.parse(params[:date]) : Date.current
        # TODO: Implement availability logic
        render json: { available: true, date: date }
      end

      private

      def room_params
        params.require(:room).permit(:name, :capacity, :has_projector, :has_video_conference, :floor)
      end
    end
  end
end