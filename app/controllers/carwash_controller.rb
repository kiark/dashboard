class CarwashController < ApplicationController

  def checks_index
    @checks = VehicleCheck.all
    render 'carwash/checks_index'
  end

  def start_check_session
    begin
      p = params.require('VehicleCheckSession').permit(:model_name,:vehicle_id,:station)
      if p[:model_name] == 'ExternalVehicle'
        v = ExternalVehicle.find(p[:vehicle_id])
        @check_session = VehicleCheckSession.create(date: Date.today,external_vehicle: v, operator: current_user.person, theoretical_duration: v.vehicle_checks.map{ |c| c.duration }.inject(0,:+))
      elsif p[:model_name] == 'Vehicle'
        v = Vehicle.find(p[:vehicle_id])
        @check_session = VehicleCheckSession.create(date: Date.today,vehicle: v, operator: current_user.person, theoretical_duration: v.vehicle_checks.map{ |c| c.duration }.inject(0,:+))
      else
        raise "Veicolo non specificato (#{p[:model_name].inspect})"
      end
      @checks = Array.new
      v.vehicle_checks(p[:station]).each do |vc|
        @checks << VehiclePerformedCheck.create(vehicle_check_session: @check_session, vehicle_check: vc, value: nil, notes: nil, performed: false)
      end
      respond_to do |format|
        format.js { render :partial => 'carwash/checks_js' }
      end
    rescue Exception => e
      @error = e.message
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def continue_check_session
    begin
      @check_session = VehicleCheckSession.find(params.require(:id))
      @checks = @check_session.vehicle_performed_checks
      respond_to do |format|
        format.js { render :partial => 'carwash/checks_js' }
      end
    rescue Exception => e
      @error = e.message
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  private

  def get_vehicle
    @vehicle = Vehicle.find(params.require(:vehicle_id))
  end

  def start_session_params

  end
end
