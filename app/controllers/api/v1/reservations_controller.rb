module Api
  module V1
    class ReservationsController < ApplicationController
      def index
        reservations = Reservation.all
        render json: reservations
      end

      def show
        reservation = Reservation.find(params[:id])
        render json: reservation
      end

      def create
        reservation = Reservation.create_with_recurrence!(reservation_params)
        render json: reservation, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ArgumentError => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end

      def cancel
        reservation = Reservation.find(params[:id])
        if reservation.can_cancel?
          reservation.update!(cancelled_at: Time.current)
          render json: reservation
        else
          render json: { errors: ["Reservation cannot be cancelled at this time"] }, status: :unprocessable_entity
        end
      end

      private

      def reservation_params
        params.require(:reservation).permit(:title, :starts_at, :ends_at, :recurring, :recurring_until, :room_id, :user_id).tap do |p|
          p[:recurring_until] = Date.parse(p[:recurring_until]) if p[:recurring_until].present?
          p[:starts_at] = Time.zone.parse(p[:starts_at]) if p[:starts_at].present?
          p[:ends_at] = Time.zone.parse(p[:ends_at]) if p[:ends_at].present?
        end
      end
    end
  end
end