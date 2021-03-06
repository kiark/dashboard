class WorkshopController < ApplicationController

  before_action :authenticate_user!
  before_action :get_worksheet, except: [:get_sheet,:load_ws_row,:create_worksheet,:index,:open_notification,:timesheet_popup,:timesheet_start,:timesheet_stop]
  before_action :get_check_session, except: [:index,:load_ws_row,:timesheet_popup,:timesheet_start,:timesheet_stop]
  before_action :get_workshop_operation, only: [:start_operation, :pause_operation, :finish_operation,  :delete_operation]
  before_action :set_protocol, except: [:index,:load_ws_row]
  before_action :set_station

  def get_sheet
    respond_to do |format|
      format.pdf do
        ws = Worksheet.find(params.require(:id))
        pdf = ws.sheet
        send_data pdf.render, filename:
        "odl_nr_#{ws.number}.pdf",
        type: "application/pdf"
      end
    end
  end

  def index
    unless params[:list].nil?
      unless params[:list][:search_number].nil? || params[:list][:search_number] == ''
        @search_number = params[:list][:search_number]
      end
      unless params[:list][:search_operator].nil? || params[:list][:search_operator] == ''
        @search_operator = params[:list][:search_operator]
      end
      unless params[:list][:search_plate].nil? || params[:list][:search_plate] == ''
        @search_plate = params[:list][:search_plate]
      end

    end

    begin

      if params[:commit] == 'Aggiorna'
        @open_worksheets = Worksheet.get_incoming({number: @search_number, operator: @search_operator, plate: @search_plate})
      else
        # @open_worksheets = Worksheet.open
        where = [
          "exit_time is null",
          "suspended = 0",
          "closingDate is null",
          "closed = 0"
        ]
        unless @search_number.nil?
          # @open_worksheets = @open_worksheets.where(number: @search_number)
          where << "(code like 'EWC*%#{@search_number.to_i}%')"
        end
        unless @search_operator.nil?
          ops = EurowinController::get_operators(@search_operator)
          c = EurowinController::get_ew_client
          # @open_worksheets = @open_worksheets.where("number in #{c.query("select protocollo from autoodl where codiceoperatore in (#{ops.map{ |o| "'#{o['Codice']}'" }.join(',')})")}")
          where << "(code in (#{c.query("select concat('EWC*',protocollo) as code from autoodl where codicemanutentore in (#{ops.map{ |o| "'#{o['Codice']}'" }.join(',')})").map{ |odl| "'#{odl['code']}'" }.join(',')}))"
          c.close
        end
        unless @search_plate.nil?
          # @open_worksheets = @open_worksheets.where("vehicle_id in (select vehicle_id from vehicle_informations where information like #{ActiveRecord::Base::sanitize("%#{@search_plate}%")})")
          # where << "(vehicle_id in (select vehicle_id from vehicle_informations where information like #{ActiveRecord::Base::sanitize("%#{@search_plate}%")}))"
          # where << "plate_number like '#{ActiveRecord::Base::sanitize("%#{@search_plate}%")}'"
        end
        qry = <<-QRY
          select worksheets.*, (
            if(
              worksheets.vehicle_type = 'Vehicle',
                (select information from vehicle_informations
                  where vehicle_informations.vehicle_id = worksheets.vehicle_id
                    and vehicle_informations.vehicle_information_type_id = (select id from vehicle_information_types where name = 'Targa')
                  order by date desc limit 1
                ),
                (select plate from external_vehicles where external_vehicles.id = worksheets.vehicle_id )
            )
          ) as plate_number
          from worksheets
          where #{where.join(' and ')}
          #{"having plate_number like #{ActiveRecord::Base::sanitize("%#{@search_plate}%")}" unless @search_plate.nil?}
          order by plate_number
        QRY

        wks = Worksheet.find_by_sql(qry)

        @open_worksheets = Array.new
        wks.each do |wos|
          v = wos.vehicle
          # raise "Veicolo con id #{wos.vehicle_id} non trovato. ODL nr. #{wos.number}" if v.nil?
          next if v.nil?
          @open_worksheets << {ws: wos, plate: wos.plate_number, vehicle: wos.vehicle_id, no_satellite: (Time.now - v.last_gps.to_i > 7.days)}
        end
      end
      respond_to do |format|
        format.html { render 'workshop/index' }
        format.js { render partial: 'workshop/index_js' }
      end
    rescue Exception => e
      respond_to do |format|
        @error = e.message+"\n"+e.backtrace.join("\n")
        format.html { render partial: 'layouts/error_html' }
        format.js { render partial: 'layouts/error' }
      end
    end
  end

  def load_ws_row
    qry = <<-QRY
      select worksheets.*, (
        if(
          worksheets.vehicle_type = 'Vehicle',
            (select information from vehicle_informations
              where vehicle_informations.vehicle_id = worksheets.vehicle_id
                and vehicle_informations.vehicle_information_type_id = (select id from vehicle_information_types where name = 'Targa')
              order by date desc limit 1
            ),
            (select plate from external_vehicles where external_vehicles.id = worksheets.vehicle_id )
        )
      ) as plate_number
      from worksheets
      where id = #{params[:id].to_i}
    QRY
    wos = Worksheet.find_by_sql(qry).first
    v = wos.vehicle
    @ws = {ws: wos, plate: wos.plate_number, vehicle: wos.vehicle_id, no_satellite: (Time.now - v.last_gps.to_i > 7.days)}
    respond_to do |format|
      format.js { render partial: 'workshop/loadable_ws_row_js'}
    end
  end

  def reset_worksheet
    begin

      num = params['id'].to_i #if @worksheet.nil?
      odl = EurowinController::get_worksheet(num)
      #raise "La scheda nr. #{params['id']} è inesistente." if odl.nil?
      EurowinController::reset_odl(num)

      unless @worksheet.nil?
        @worksheet.update(opening_date: nil, paused: true, last_starting_time: nil, last_stopping_time: nil, real_duration: 0)
        @worksheet.workshop_operations.each{ |wo| wo.delete}
      end

      respond_to do |format|
        if params[:area] == 'on_processing'
          format.js { render partial: 'workshop/worksheet_op_js' }
        else
          format.js { render partial: 'workshop/close_worksheet_js' }
        end
      end

    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def open_notification

    begin
      # Get worksheet from vehicle
      vehicle = MssqlReference.where("remote_object_id = #{params.require(:vehicle)} and (local_object_type = 'Vehicle' or local_object_type = 'ExternalVehicle')").first.local_object

      # Get first open worksheet
      # @worksheet = Worksheet.where(vehicle: vehicle, closed: false, exit_time: nil).where().order(opening_date: :asc).first
      odl = EurowinController::get_last_open_odl_by_vehicle(params.require(:vehicle))

      # Get the notification
      sgn = EurowinController::get_notification(params.require(:sgn))

      if odl.nil?


        vehicle_refs = EurowinController::get_vehicle(vehicle)

        payload = {
          'Descrizione': sgn['DescrizioneSegnalazione'],
          'ProtocolloODL': '0',
          'AnnoODL': '0',
          'DataEntrataVeicolo': Time.now.strftime('%Y-%m-%d'),
          'CodiceAutista': current_user.person.mssql_references.first.remote_object_id.to_s,
          'CodiceAutomezzo': vehicle_refs['CodiceAutomezzo'],
          'CodiceTarga': vehicle_refs['Targa'],
          'Chilometraggio': vehicle_refs['Km'].to_s,
          'CodiceOfficina': EurowinController::get_workshop(:workshop),
          'TipoDanno': sgn['TipoDanno'],
          'FlagSvolto': 'false'
        }

        odl = EurowinController::create_worksheet(payload)

        damage_type = EurowinController::get_tipo_danno(sgn['TipoDanno'],true)
        @worksheet  = Worksheet.create(code: "EWC*#{odl['Protocollo']}",vehicle: vehicle, notes: damage_type['Descrizione']+" - "+sgn['DescrizioneSegnalazione'], opening_date: Date.current, log: "Scheda creata da #{current_user.person.list_name}, il #{Time.now.strftime("%d/%m/%Y alle %H:%M:%S")}.\n")


        vec = vehicle.vehicle_checks('workshop')
        if vec.size < 1
          raise "Non ci sono controlli da fare per questo mezzo (targa: #{v.plate})."
        end

        if vehicle.class == ExternalVehicle

          @check_session = VehicleCheckSession.create(date: Date.today,external_vehicle: vehicle, operator: current_user, theoretical_duration: vehicle.vehicle_checks('workshop').map{ |c| c.duration }.inject(0,:+), log: "Sessione iniziata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", myofficina_reference: @worksheet.number.to_i, worksheet: @worksheet, station: @station)

        elsif vehicle.class == Vehicle

          @check_session = VehicleCheckSession.create(date: Date.today,vehicle: vehicle, operator: current_user, theoretical_duration: vehicle.vehicle_checks('workshop').map{ |c| c.duration }.inject(0,:+), log: "Sessione iniziata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", myofficina_reference: @worksheet.number.to_i, worksheet: @worksheet, station: @station, real_km: vehicle.mileage)

        end
        @checks = Hash.new
        vec.each do |vc|
          @checks[vc.code] = Array.new if @checks[vc.code].nil?
          @checks[vc.code] << VehiclePerformedCheck.create(vehicle_check_session: @check_session, vehicle_id: vehicle.id, vehicle_check: vc, value: nil, notes: nil, performed: 0, mandatory: vehicle.mandatory?(vc) )
        end
      else
        @worksheet = Worksheet.find_by(code: "EWC*#{odl['Protocollo']}")
      end

      payload = {
        'ProtocolloODL': odl['Protocollo'].to_s,
        'AnnoODL': odl['Anno'].to_s,
        'ProtocolloSGN': sgn['Protocollo'].to_s,
        'AnnoSGN': sgn['Anno'].to_s,
        'CodiceAutomezzo': params.require(:vehicle).to_s,
        'CodiceOfficina': EurowinController::get_workshop(:workshop),
        'FlagRiparato': 'false',
        'FlagStampato': 'false',
        'FlagChiuso': 'false'
      }

      sgn = EurowinController::create_notification(payload)
      # WorkshopOperation.create(name: 'Lavorazione', worksheet: @worksheet, myofficina_reference: sgn['Protocollo'], user: current_user, log: "Operazione creata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")
      #
      # respond_to do |format|
      #   format.js { render partial: 'workshop/worksheet_js' }
      # end
      open_worksheet
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def open_worksheet

    begin
      if @worksheet.mileage.to_i == 0
        @worksheet.update(mileage: @worksheet.vehicle.mileage)
      end
      if @worksheet.opening_date.nil?
        @worksheet.update(opening_date: Date.today, log: @worksheet.log.to_s+"\nScheda aperta da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")

        odl = EurowinController::get_worksheet(@worksheet.number)
        EurowinController::create_worksheet('DataEntrataVeicolo': Date.today.strftime('%Y-%m-%d'),'AnnoODL': odl['Anno'].to_s, 'ProtocolloODL': odl['Protocollo'].to_s, 'DataIntervento': odl['DataIntervento'])
      else
        @worksheet.update(log: @worksheet.log.to_s+"\nScheda riaperta da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")
      end
      @worksheet.notifications.each do |sgn|
        if WorkshopOperation.to_notification(sgn['Protocollo']).count < 1
          WorkshopOperation.create(name: "Lavorazione", worksheet: @worksheet, myofficina_reference: sgn['Protocollo'], user: nil, log: "Operazione creata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")
        end
      end

      # # Assign checks operation if missing
      # wo_nil = WorkshopOperation.find_by(worksheet: @worksheet, myofficina_reference: nil, user: nil)
      # if wo_nil.nil?
      #   WorkshopOperation.create(name: 'Controlli', worksheet: @worksheet, myofficina_reference: nil, user: current_user) if WorkshopOperation.find_by(name: 'Controlli', worksheet: @worksheet, myofficina_reference: nil, user: current_user).nil?
      # else
      #   wo_nil.update(user: current_user)
      # end

      # Create checks operation if missing
      WorkshopOperation.create(name: 'Controlli', worksheet: @worksheet, myofficina_reference: nil, user: nil) if WorkshopOperation.find_by(name: 'Controlli', worksheet: @worksheet, myofficina_reference: nil).nil?

      v = @worksheet.vehicle
      vec = v.vehicle_checks('workshop')
      if vec.size < 1
        raise "Non ci sono controlli da fare per questo mezzo (targa: #{v.plate})."
      end

      if @check_session.nil?
        if v.class == ExternalVehicle

          @check_session = VehicleCheckSession.create(date: Date.today,external_vehicle: v, operator: current_user, theoretical_duration: v.vehicle_checks('workshop').map{ |c| c.duration }.inject(0,:+), log: "Sessione iniziata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", myofficina_reference: @worksheet.number.to_i, worksheet: @worksheet, station: @station)

        elsif v.class == Vehicle

          @check_session = VehicleCheckSession.create(date: Date.today,vehicle: v, operator: current_user, theoretical_duration: v.vehicle_checks('workshop').map{ |c| c.duration }.inject(0,:+), log: "Sessione iniziata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", myofficina_reference: @worksheet.number.to_i, worksheet: @worksheet, station: @station, real_km: v.mileage)

        end

        @checks = Hash.new
        vec.each do |vc|
          @checks[vc.code] = Array.new if @checks[vc.code].nil?
          @checks[vc.code] << VehiclePerformedCheck.create(vehicle_check_session: @check_session, vehicle_id: v.id, vehicle_check: vc, value: nil, notes: nil, performed: 0, mandatory: v.mandatory?(vc) )
        end

      else

        @check_session.update(log: @check_session.log.to_s+"\nSessione ripresa da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")

      end
      @worksheet.update(last_starting_time: Time.now, last_stopping_time: nil, paused: false)

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

  def info_worksheet
    begin
      @vehicle = @worksheet.vehicle
      respond_to do |format|
        format.js { render partial: 'workshop/infobox_worksheet' }
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
      WorkshopOperation.create(name: params.require('name'), worksheet: @worksheet, myofficina_reference: @protocol == 'checks' ? nil : @protocol, user: current_user, log: "Operazione creata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")
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

  def create_notification
    begin
      vehicle_refs = EurowinController::get_vehicle(@worksheet.vehicle)
      payload = {
        'Descrizione': params.require('description'),
        'ProtocolloODL': params.require('protocol'),
        'AnnoODL': Date.current.strftime('%Y'),
        'UserInsert': current_user.person.complete_name.upcase.gsub("'","\'"),
        'UserPost': 'OFFICINA',
        'CodiceAutista': current_user.person.mssql_references.first.remote_object_id.to_s,
        'CodiceAutomezzo': vehicle_refs['CodiceAutomezzo'],
        'CodiceTarga': vehicle_refs['Targa'],
        'TipoDanno': params.require('damage_type').to_s,
        'Chilometraggio': vehicle_refs['Km'].to_s,
        'CodiceOfficina': EurowinController::get_workshop(:workshop),
        'FlagRiparato': 'false',
        'FlagStampato': 'false',
        'FlagChiuso': 'false'
      }

      sgn = EurowinController::create_notification(payload)
      WorkshopOperation.create(name: 'Lavorazione', worksheet: @worksheet, myofficina_reference: sgn['Protocollo'], user: nil, log: "Operazione creata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")

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

  def create_worksheet
    begin
      if params['Worksheet']['vehicle'].nil? || params['Worksheet']['vehicle'] == ''
        vehicle = Vehicle.find_by_plate(params.require('Worksheet')['vehicle_plate'].gsub(' ',''))
      else
        vehicle = params.require('Worksheet').permit(:model_name) == 'ExternalVehicle' ? ExternalVehicle.find(params.require('Worksheet').permit(:vehicle)['vehicle'].to_i) : Vehicle.find(params.require('Worksheet').permit(:vehicle)['vehicle'].to_i)
      end

      vehicle_refs = EurowinController::get_vehicle(vehicle)

      payload = {
        'Descrizione': params.require('Worksheet').permit('description')['description'],
        'ProtocolloODL': '0',
        'AnnoODL': '0',
        'DataEntrataVeicolo': Time.now.strftime('%Y-%m-%d'),
        'CodiceAutista': current_user.person.mssql_references.first.remote_object_id.to_s,
        'CodiceAutomezzo': vehicle_refs['CodiceAutomezzo'],
        'CodiceTarga': vehicle_refs['Targa'],
        'Chilometraggio': vehicle_refs['Km'].to_s,
        'CodiceOfficina': EurowinController::get_workshop(:workshop),
        'TipoDanno': params.require('Worksheet').permit(:damage_type)['damage_type'],
        'FlagSvolto': 'false'
      }

      odl = EurowinController::create_worksheet(payload)

      damage_type = EurowinController::get_tipo_danno(params.require('Worksheet').permit(:damage_type)['damage_type'],true)
      @worksheet  = Worksheet.create(code: "EWC*#{odl['Protocollo']}",vehicle: vehicle, notes: damage_type['Descrizione']+" - "+params.require('Worksheet').permit('description')['description'], opening_date: Date.current, log: "Scheda creata da #{current_user.person.list_name}, il #{Time.now.strftime("%d/%m/%Y alle %H:%M:%S")}.\n")


      vec = vehicle.vehicle_checks('workshop')
      if vec.size < 1
        raise "Non ci sono controlli da fare per questo mezzo (targa: #{v.plate})."
      end

      WorkshopOperation.create(name: 'Controlli', worksheet: @worksheet, myofficina_reference: nil, user: nil)

      if vehicle.class == ExternalVehicle

        @check_session = VehicleCheckSession.create(date: Date.today,external_vehicle: vehicle, operator: current_user, theoretical_duration: vehicle.vehicle_checks('workshop').map{ |c| c.duration }.inject(0,:+), log: "Sessione iniziata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", myofficina_reference: @worksheet.number.to_i, worksheet: @worksheet, station: @station)

      elsif vehicle.class == Vehicle

        @check_session = VehicleCheckSession.create(date: Date.today,vehicle: vehicle, operator: current_user, theoretical_duration: vehicle.vehicle_checks('workshop').map{ |c| c.duration }.inject(0,:+), log: "Sessione iniziata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", myofficina_reference: @worksheet.number.to_i, worksheet: @worksheet, station: @station, real_km: vehicle.mileage)

      end
      @checks = Hash.new
      vec.each do |vc|
        @checks[vc.code] = Array.new if @checks[vc.code].nil?
        @checks[vc.code] << VehiclePerformedCheck.create(vehicle_check_session: @check_session, vehicle_id: vehicle.id, vehicle_check: vc, value: nil, notes: nil, performed: 0, mandatory: vehicle.mandatory?(vc) )
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

  def add_sgn_to_worksheet
    sgn = JSON.parse params[:value]
    odl = @worksheet.ew_worksheet
    old_odl = EurowinController::get_worksheet(sgn['SchedaInterventoProtocollo'])
    case @station
    when 'workshop' then
      station = 'OFFICINA'
    when 'carwash' then
      station = 'PUNTO CHECK-UP'
    else
      station = 'N/D'
    end
    @worksheet.update(log: "#{@worksheet.log}\n Segnalazione '#{sgn['DescrizioneSegnalazione']}' (#{sgn['Protocollo']}) spostata da #{current_user.person.list_name} il #{Time.now.strftime("%Y/%m/%d")} alle #{Time.now.strftime("%H:%M:%S")}.")
    sgn = EurowinController::create_notification({
      'Descrizione': sgn['Descrizione'],
      'ProtocolloODL': odl['Protocollo'].to_s,
      'AnnoODL': odl['Anno'].to_s,
      'ProtocolloSGN': sgn['Protocollo'].to_s,
      'AnnoSGN': sgn['Anno'].to_s,
      'UserInsert': current_user.person.complete_name.upcase,
      'UserPost': station,
      'CodiceAutista': current_user.person.mssql_references.first.remote_object_id.to_s,
      'CodiceAutomezzo': sgn['CodiceAutomezzo'],
      'CodiceTarga': sgn['Targa'],
      'CodiceOfficina': EurowinController::get_workshop(@station.to_sym),
      'FlagStampato': 'false'
    })

    WorkshopMailer.notify_moving_sgn(sgn,old_odl).deliver_now
    begin
      respond_to do |format|
        if params[:area].nil?
          format.js { render partial: 'workshop/worksheet_js' }
        elsif @station.to_s == 'carwash'
          format.js { render 'carwash/checks_index_js' }
        elsif params[:area] == 'on_processing'
          @notifications = @worksheet.notifications(:all)
          format.js { render partial: 'workshop/xbox_js' }
        end
      end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def deassociate_notification
    begin

      # update worksheet's log
      @worksheet.update(log: "#{@worksheet.log}\n Segnalazione '#{params.require('description')}' (#{params.require('protocol')}) spostata da #{current_user.person.list_name} il #{Time.now.strftime("%Y/%m/%d")} alle #{Time.now.strftime("%H:%M:%S")}.")

      vehicle_refs = EurowinController::get_vehicle(@worksheet.vehicle)
      if params['external_workshop'].nil?
        odl = EurowinController::last_open_odl_not(@worksheet.number)

        odl = EurowinController::create_worksheet({
          'Descrizione': params.require('description'),
          'ProtocolloODL': "0",
          'AnnoODL': "0",
          'CodiceAutomezzo': vehicle_refs['CodiceAutomezzo'],
          'CodiceAutista': vehicle_refs['CodiceAutista'],
          'CodiceTarga': vehicle_refs['Targa'],
          'Chilometraggio': vehicle_refs['Km'].to_s,
          'TipoDanno': params.require('damage_type').to_s,
          'CodiceOfficina': EurowinController::get_workshop(:workshop),
          'FlagSvolto': 'false'
          }) if odl.nil?
        protocollo_odl = odl['Protocollo'].to_s
        anno_odl = odl['Anno'].to_s

      else
        protocollo_odl = "-1"
        anno_odl = "-1"

      end

      duplicate_sgn = nil
      # Stop or delete all operations
      wos = WorkshopOperation.get_from_sgn(params.require('protocol'))

      wos.each do |wo|
        if wo.real_duration.to_i == 0
          wo.delete
          next
        end
        if wo.paused
          duration = wo.real_duration
        else
          duration = wo.real_duration + Time.now.to_i - wo.last_starting_time.to_i
        end
        wo.update(ending_time: DateTime.now, real_duration: duration, paused: true, last_starting_time: nil, last_stopping_time: Time.now, log: "#{wo.log}\n Operazione conclusa da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.", notes: params['notes'].nil? ? '' : params['notes'].tr("'","''"))
        # @worksheet.update(real_duration: params.require('worksheet_duration').to_i)
        @worksheet.update(last_starting_time: Time.now, last_stopping_time: nil, real_duration: @worksheet.real_duration + Time.now.to_i - @worksheet.last_starting_time.to_i, paused: false) unless @worksheet.paused
        @worksheet.update(log: "#{@worksheet.log}\n #{wo.log}")
        #close notification there are no more operations
        duplicate_sgn = wo.ew_notification
      end

      if duplicate_sgn.nil?

        sgn = EurowinController::create_notification({
          'Descrizione': params.require('description'),
          'ProtocolloODL': protocollo_odl,
          'AnnoODL': anno_odl,
          'ProtocolloSGN': params.require('protocol'),
          'AnnoSGN': params.require('year'),
          'UserInsert': current_user.person.complete_name.upcase,
          'UserPost': 'OFFICINA',
          'CodiceAutista': current_user.person.mssql_references.first.remote_object_id.to_s,
          'CodiceAutomezzo': vehicle_refs['CodiceAutomezzo'],
          'CodiceTarga': vehicle_refs['Targa'],
          'Chilometraggio': vehicle_refs['Km'].to_s,
          'TipoDanno': params['damage_type'].to_s,
          'CodiceOfficina': EurowinController::get_workshop(:workshop),
          'FlagStampato': 'false'
        })

      else

        EurowinController::create_notification({
          'ProtocolloODL': duplicate_sgn['SchedaInterventoProtocollo'].to_s,
          'AnnoODL': duplicate_sgn['SchedaInterventoAnno'].to_s,
          'ProtocolloSGN': duplicate_sgn['Protocollo'].to_s,
          'AnnoSGN': duplicate_sgn['Anno'].to_s,
          'DataIntervento': duplicate_sgn['DataSegnalazione'].to_s,
          'FlagRiparato': 'false',
          'FlagSvolto': 'true',
          'CodiceOfficina': "0"
        })

        sgn = EurowinController::create_notification({
          'Descrizione': params.require('description'),
          'ProtocolloODL': protocollo_odl,
          'AnnoODL': anno_odl,
          'ProtocolloSGN': '-1',
          'AnnoSGN': '-1',
          'UserInsert': current_user.person.complete_name.upcase,
          'UserPost': 'OFFICINA',
          'CodiceAutista': current_user.person.mssql_references.first.remote_object_id.to_s,
          'CodiceAutomezzo': vehicle_refs['CodiceAutomezzo'],
          'CodiceTarga': vehicle_refs['Targa'],
          'Chilometraggio': vehicle_refs['Km'].to_s,
          'TipoDanno': params['damage_type'].to_s,
          'CodiceOfficina': EurowinController::get_workshop(:workshop),
          'FlagStampato': 'false'
        })
      end
      # WorkshopMailer.notify_moving_sgn(sgn,odl).deliver_now
      respond_to do |format|
        if params[:area] == 'on_processing'

          @notifications = @worksheet.notifications(:all)
          format.js { render partial: 'workshop/xbox_js' }

        elsif @station.to_s == 'carwash'

          format.js { render 'carwash/checks_index_js' }

        elsif params[:area].nil?

          format.js { render partial: 'workshop/worksheet_js' }

        end
      end
    rescue Exception => e
      @error = e.message+"\n\n#{e.backtrace}"
      respond_to do |format|
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  def update_operation_time
    @worksheet.operations.each do |wo|
      unless wo.paused
        wo.update(starting_time: wo.last_starting_time) if wo.starting_time.nil?
        wo.update(real_duration: wo.real_duration.to_i + Time.now.to_i - wo.last_starting_time.to_i , last_starting_time: Time.now)
      end
    end
    # @worksheet.update(last_starting_time: Time.now, last_stopping_time: nil, real_duration: @worksheet.real_duration.to_i + Time.now.to_i - @worksheet.last_starting_time.to_i, paused: false) unless @worksheet.paused
    
    respond_to do |format|
      format.js { render partial: 'workshop/worksheet_js' }
    end
  end

  def start_operation
    begin

      @workshop_operation.start(ts: DateTime.now, user: current_user)

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

  def pause_operation
    begin

      @workshop_operation.pause(ts: DateTime.now, user: current_user)

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

  def finish_operation
    begin

      @workshop_operation.close(ts: DateTime.now, user: current_user, notes: params['notes'].tr("'","''"))

      respond_to do |format|
        if params[:area].nil?
          format.js { render partial: 'workshop/worksheet_js' }
        elsif params[:area] == 'on_processing'
          @notifications = @worksheet.notifications(:all)
          format.js { render partial: 'workshop/xbox_js' }
        end
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
      @worksheet.update(log: "#{@worksheet.log}\n Operazione nr. #{@workshop_operation.id}, '#{@workshop_operation.name}', eliminata da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")
      if @workshop_operation.siblings.count < 2
        @workshop_operation.update(user: nil)
      else
        @workshop_operation.destroy
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

  def save_worksheet
    begin
      # JSON.parse(params.require('operation_times')).each do |ot|
      #   WorkshopOperation.find(ot['id'].to_i).update(real_duration: ot['time'].to_i)
      # end

      # if @worksheet.last_starting_time.nil?
      #   duration = @worksheet.real_duration
      # else
      #   duration = @worksheet.real_duration + Time.now.to_i - @worksheet.last_starting_time.to_i
      # end

      duration = @worksheet.workshop_operations.map{ |wo| wo.real_duration}.inject(0,:+)
      if params[:area] == 'on_processing' || current_user.has_role?('amministratore officina')
        ops = @worksheet.operations
      else
        ops = @worksheet.operations(current_user)
      end


      @worksheet.update(last_starting_time: nil, last_stopping_time: Time.now, real_duration: duration, paused: true)

      if params.require('perform') == 'stop'
        ops.each do |wo|
          # wo.update(ending_time: Time.now)
          wo.close(time: Time.now, user: current_user)
          unless wo.myofficina_reference.nil?
            sgn = EurowinController::get_notification(wo.myofficina_reference)
            EurowinController::create_notification({
              'ProtocolloODL': sgn['SchedaInterventoProtocollo'].to_s,
              'AnnoODL': sgn['SchedaInterventoAnno'].to_s,
              'ProtocolloSGN': sgn['Protocollo'].to_s,
              'AnnoSGN': sgn['Anno'].to_s,
              'DataIntervento': sgn['DataSegnalazione'].to_s,
              'FlagRiparato': 'true',
              'CodiceOfficina': "0"
            }) unless sgn.nil?
          end
        end
        invoicing = params['invoice'] == 'true' ? true : false

        @worksheet.update(invoicing: invoicing, exit_time: DateTime.now, log: "#{@worksheet.log}\n Scheda chiusa da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.")
        vcs = @worksheet.vehicle_check_session
        unless vcs.nil?
          vcs.vehicle_performed_checks.each do |vpc|
            vpc.create_notification()
          end
          vcs.update(finished: DateTime.now, real_duration: 0, log: vcs.log.to_s+"\nSessione conclusa da #{current_user.person.complete_name}, il #{Date.today.strftime('%d/%m/%Y')} alle #{DateTime.now.strftime('%H:%M:%S')}.") unless vcs.nil?
        end
        odl = @worksheet.ew_worksheet
        EurowinController::create_worksheet({
          'ProtocolloODL': odl['Protocollo'].to_s,
          'AnnoODL': odl['Anno'].to_s,
          'DataIntervento': odl['DataIntervento'].to_s,
          'DataUscitaVeicolo': Date.today.strftime("%Y-%m-%d"),
          'FlagSvolto': 'true',
          'CodiceOfficina': "0"
        }) unless odl.nil?
        @worksheet.output_orders.each do |oo|
          oo.update(processed: true)
        end
        pdf = @worksheet.sheet
        unless pdf.nil?
          # File.open("/mnt/documents/ODL/#{@worksheet.vehicle.plate}/ODL_#{@worksheet.number}.pdf",'w').write(pdf.render.force_encoding('utf-8'))
          @worksheet.write_sheet
          WorkshopMailer.send_worksheet(@worksheet,pdf).deliver_now
        end
        WorkshopMailer.send_to_logistics(@worksheet).deliver_now
      else
        # @worksheet.update(last_starting_time: nil, last_stopping_time: Time.now, real_duration: @worksheet.real_duration + Time.now.to_i - @worksheet.last_starting_time.to_i, paused: true)
        ops.each do |wo|
          # wo.update(real_duration: wo.real_duration + Time.now.to_i - wo.last_starting_time.to_i , last_stopping_time: Time.now, last_starting_time: nil, paused: true) unless wo.paused
          wo.pause
        end
      end

      respond_to do |format|
        if params[:area] == 'on_processing'
          format.js { render partial: 'workshop/worksheet_op_js' }
        elsif @station.to_s == 'carwash'
          format.js { render 'carwash/checks_index_js' }
        else
          format.js { render partial: 'workshop/close_worksheet_js' }
        end
        # format.js { redirect_to worksheets_path }
      end
    rescue Exception => e

      @error = "WorkshopController.rb 656\n\n"+e.message+"\n\n\n"+e.backtrace.join("\n\n")
      ErrorMailer.error_report(@error,"Chiusura scheda - ODL nr. #{@worksheet.number}").deliver_now
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

  def get_workshop_operation
    @workshop_operation = WorkshopOperation.find(params.require(:operation).to_i)
  end

  def set_protocol
    if params['protocol'] == 'checks'
      @protocol = 'checks'
    else
      @protocol = params['protocol'].to_i
    end
  end

  def set_station
    # @station = params['station'].nil? ? 'workshop' : params['station']
    if params['station'].nil?
      if current_user.has_role?('odl aperti') || current_user.has_role?('amministratore officina')
        @station = 'workshop'
      else
        @station = 'carwash'
      end
    else
      @station = params.require('station').to_s
    end
  end

end
