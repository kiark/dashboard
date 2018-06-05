class WorkshopController < ApplicationController

  before_action :get_worksheet
  before_action :get_check_session
  before_action :set_protocol
  before_action :set_station

  def open_worksheet

    begin
      v = @worksheet.vehicle
      vec = v.vehicle_checks('workshop')
      if vec.size < 1
        raise "Non ci sono controlli da fare per questo mezzo (targa: #{v.plate})."
      end

      if @check_session.nil?
        if v.class == ExternalVehicle

          @check_session = VehicleCheckSession.create(date: Date.today,external_vehicle: v, operator: current_user, theoretical_duration: v.vehicle_checks('workshop').map{ |c| c.duration }.inject(0,:+), log: "Sessione iniziata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", myofficina_reference: @worksheet.number.to_i, worksheet: @worksheet)

        elsif v.class == Vehicle

          @check_session = VehicleCheckSession.create(date: Date.today,vehicle: v, operator: current_user, theoretical_duration: v.vehicle_checks('workshop').map{ |c| c.duration }.inject(0,:+), log: "Sessione iniziata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", myofficina_reference: @worksheet.number.to_i, worksheet: @worksheet)

        end

        @checks = Hash.new
        vec.each do |vc|
          @checks[vc.code] = Array.new if @checks[vc.code].nil?
          @checks[vc.code] << VehiclePerformedCheck.create(vehicle_check_session: @check_session, vehicle_check: vc, value: nil, notes: nil, performed: 0, mandatory: v.mandatory?(vc) )
        end

      else

        @check_session.update(log: @check_session.log.to_s+"\nSessione ripresa da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")

      end


      respond_to do |format|
        format.js { render partial: 'workshop/worksheet_js' }
      end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def create_operation
    begin
      WorkshopOperation.create(name: params.require('name'), worksheet: @worksheet, myofficina_reference: params.require('protocol'), user: current_user, log: "Operazione creata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('$H:%M:%S')}.")
      respond_to do |format|
        format.js { render partial: 'workshop/worksheet_js' }
      end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def start_operation
    begin
      wo = WorkshopOperation.find(params.require(:operation).to_i)
      wo.update(ending_time: nil, real_duration: params.require('time').to_i, log: "Operazione #{wo.starting_time.nil?? 'iniziata' : 'ripresa'} da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('$H:%M:%S')}.")
      wo.update(starting_time: DateTime.now) if wo.starting_time.nil?
      @worksheet.update(real_duration: params.require('worksheet_duration').to_i)
      # respond_to do |format|
      #   format.js { render partial: 'workshop/worksheet_js' }
      # end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def pause_operation
    begin
      WorkshopOperation.find(params.require(:operation).to_i).update(real_duration: params.require('time').to_i, log: "Operazione interrotta da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('$H:%M:%S')}.")
      @worksheet.update(real_duration: params.require('worksheet_duration').to_i)
      # respond_to do |format|
      #   format.js { render partial: 'workshop/worksheet_js' }
      # end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def finish_operation
    begin
      WorkshopOperation.find(params.require(:operation).to_i).update(ending_time: DateTime.now, real_duration: params.require('time').to_i, log: "Operazione conclusa da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('$H:%M:%S')}.")
      @worksheet.update(real_duration: params.require('worksheet_duration').to_i)
      respond_to do |format|
        format.js { render partial: 'workshop/worksheet_js' }
      end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def delete_operation
    begin
      wo = WorkshopOperation.find(params.require(:operation).to_i)
      @worksheet.update(log: "Operazione nr. #{wo.id}, '#{wo.name}', eliminata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('$H:%M:%S')}.")
      wo.destroy
      respond_to do |format|
        format.js { render partial: 'workshop/worksheet_js' }
      end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def save_worksheet
    begin
      JSON.parse(params.require('operation_times')).each do |ot|
        WorkshopOperation.find(ot['id'].to_i).update(real_duration: ot['time'].to_i)
      end
      if params.require('perform') == 'stop'
        @worksheet.update(real_duration: params.require('worksheet_duration').to_i, exit_time: DateTime.now, log: "Scheda chiusa da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('$H:%M:%S')}.")
      else
        @worksheet.update(real_duration: params.require('worksheet_duration').to_i, log: "Scheda sospesa da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('$H:%M:%S')}.")
      end
      respond_to do |format|
        format.js { render partial: 'workshop/close_worksheet_js' }
        # format.js { redirect_to worksheets_path }
      end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  private

  def get_worksheet
    @worksheet = Worksheet.find_or_create_by_code(params.require(:id))
  end

  def get_check_session
    @check_session = VehicleCheckSession.find_by(worksheet: @worksheet)
    @checks = @check_session.vehicle_ordered_performed_checks unless @check_session.nil?
  end

  def set_protocol
    @protocol = params['protocol'].to_i
  end

  def set_station
    @station = 'workshop'
  end

end