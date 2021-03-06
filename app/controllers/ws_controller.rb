class WsController < ApplicationController
  skip_before_action :authenticate_user!, :only => :update_fares
  protect_from_forgery except: :update_fares
  before_action :set_status, :only => [:index,:index_load,:close_fare]
  before_action :get_action, only: [:update_user]
  before_action :get_holder, only: [:update_user]

  def autocomplete_person_company
    array = Company.filter(params.permit(:term)[:term]).map{ |p| { id: p.id.to_s, label: p.list_name, value: p.class.to_s+'#'+p.list_name, name: p.name} }
    array += Person.filter(params.permit(:term)[:term]).map{ |p| { id: p.id.to_s, label: p.list_name, value: p.class.to_s+'#'+p.list_name, name: p.name} }

    render :json => array
  end

  def index
    # mdc = MdcWebservice.new
    #
    # @results = Array.new
    # # @results << mdc.get_fares_data({applicationID: 'FARES', deviceCode: '', status: @status}).reverse[0,10]
    # # byebug
    # MdcUser.assigned.each do |p|
    #   r = mdc.get_fares_data({applicationID: 'FARES', deviceCode: p.user.upcase, status: @status}).reverse[0,10]
    #   @results << r unless r.empty?
    # end
    # mdc.close_session
    render 'mdc/index'
  end

  def self.count_open_documents
    count = 0
    mdc = MdcWebservice.new
    MdcUser.assigned.each do |p|
      count = mdc.get_fares_data({applicationID: 'FARES', deviceCode: p.user.upcase, status: 0}).count
      p.update(open_documents: count)
    end
    mdc.close_session
  end

  def index_load
    # @result = Array.new

    mdc = MdcWebservice.new
    @result = mdc.get_fares_data({applicationID: 'FARES', deviceCode: params.require(:user_id).upcase, status: 0})#.reverse[0,10]

    mdc.close_session

    @mdc_user = MdcUser.find_by(user: params.require(:user_id))
    @mdc_user.update(open_documents: @result.count)

    respond_to do |format|
      # format.js { render partial: 'mdc/index_part_js' }
      format.html { render 'mdc/index' }
    end
  end

  # Create notification from MDC report
  def create_notification

    begin
      # Get report and vehicle from params
      rep = MdcReport.find(params.require(:id).to_i)
      rep.create_notification(current_user)
      rep.update(managed_at: Time.now, user: current_user)

      @results = get_filter
      respond_to do |format|
        format.js {render partial: 'mdc/report_index_js'}
      end
    rescue Exception => e
      @error = e.message+"\n"+e.backtrace.join("\n")
      respond_to do |format|
        format.js {render partial: 'layouts/error'}
      end
    end
  end

  # Set MDC report as managed
  def manage_report

    # Get report from params and update it
    rep = MdcReport.find(params.require(:id).to_i)
    if rep.managed?
      rep.update(managed_at: nil, user: nil)
    else
      rep.update(managed_at: Time.now, user: current_user)
    end

    @results = get_filter
    respond_to do |format|
      format.js {render partial: 'mdc/report_index_js'}
    end
  end

  # GET request action
  def notification_index
    @results = get_filter

    respond_to do |format|
      format.html {render 'mdc/report_index'}
      format.js {render partial: 'mdc/report_index_js'}
    end
  end

  # POST (JS) request action
  def notification_filter

    @results = get_filter

    respond_to do |format|
      format.html {render partial: 'mdc/report_index'}
      format.js {render partial: 'mdc/report_index_js'}
    end

  end

  # prepare new report form
  def new_report
    respond_to do |format|
      format.html {render partial: 'mdc/new_report'}
      format.js {render partial: 'mdc/new_report'}
    end
  end

  # prepare change report form
  def change_report
    @office = params.require(:office)
    @report = MdcReport.find(params.require(:id))
    respond_to do |format|
      format.html {render partial: 'mdc/change_report'}
      format.js {render partial: 'mdc/change_report'}
    end
  end

  # Register new mdc report
  def create_report

    begin
      pars = report_params
      rep = MdcReport.create(pars[:report])

      # Write photos
      unless pars[:photos].nil?

        if rep.vehicle.nil?
          path = "Sede"
        else
          vehicle = rep.vehicle
          path = "Mezzi/#{vehicle.mssql_references.count > 0 ? vehicle.mssql_references.first.remote_object_id : '0000'} - #{vehicle.split_plate}"
        end
        cpath = "#{ENV['RAILS_REPORT_PHOTOS_PATH']}/#{path}/#{rep.sent_at.strftime("%Y%m%d")}"
        rpath = "FotoSegnalazioni\\#{path.gsub('/',"\\")}\\#{rep.sent_at.strftime("%Y%m%d")}"
        url = "/FotoSegnalazioni/#{path}/#{rep.sent_at.strftime("%Y%m%d")}"
        `mkdir -p #{cpath.gsub(' ','\ ')}/`

        pars[:photos].each do |photo|
          # Check whether filename already exists
          serial = 1

          ext = File.extname(photo.tempfile)
          while File.file? "#{cpath}/foto_#{serial.to_s.rjust(2,"0")}#{ext}" do
            serial += 1
          end
           filename = "foto_#{serial.to_s.rjust(2,"0")}#{ext}"
          # Copy temp file
          FileUtils.cp photo.tempfile, "#{cpath}/#{filename}"
          # fh = File.open("#{cpath}/foto_#{serial.to_s.rjust(2,"0")}.jpg",'wb')
          # fh.write(data)
          # fh.close

          MdcReportImage.create(mdc_report: rep, url: "#{url}/#{filename}", path: "#{cpath}/#{filename}")

        end
        rep.update(description: "#{rep.description}\n#{rpath}")
      end
      @results = get_filter
      respond_to do |format|
        format.html {render 'mdc/report_index'}
        format.js {render partial: 'mdc/create_report_js'}
      end
    rescue Exception => e
      @error = e.message+"\n"+e.backtrace.join("\n")
      respond_to do |format|
        format.html {render 'mdc/report_index'}
        format.js { render :partial => 'layouts/error' }
      end
    end
  end

  # Change mdc report type
  def edit_report
    begin
      pars = report_params
      rep = MdcReport.find(params.require(:id))

      # Don't update send time
      pars[:report][:sent_at] = rep.sent_at

      rep.update(pars[:report])

      # Write photos
      unless pars[:photos].nil?

        if rep.vehicle.nil?
          path = "Sede"
        else
          vehicle = rep.vehicle
          path = "Mezzi/#{vehicle.mssql_references.count > 0 ? vehicle.mssql_references.first.remote_object_id : '0000'} - #{vehicle.split_plate}"
        end
        cpath = "#{ENV['RAILS_REPORT_PHOTOS_PATH']}/#{path}/#{rep.sent_at.strftime("%Y%m%d")}"
        rpath = "FotoSegnalazioni\\#{path.gsub('/',"\\")}\\#{rep.sent_at.strftime("%Y%m%d")}"
        url = "/FotoSegnalazioni/#{path}/#{rep.sent_at.strftime("%Y%m%d")}"
        `mkdir -p #{cpath.gsub(' ','\ ')}/`

        pars[:photos].each do |photo|
          # Check whether filename already exists
          serial = 1

          ext = File.extname(photo.tempfile)
          while File.file? "#{cpath}/foto_#{serial.to_s.rjust(2,"0")}#{ext}" do
            serial += 1
          end
           filename = "foto_#{serial.to_s.rjust(2,"0")}#{ext}"
          # Copy temp file
          FileUtils.cp photo.tempfile, "#{cpath}/#{filename}"
          # fh = File.open("#{cpath}/foto_#{serial.to_s.rjust(2,"0")}.jpg",'wb')
          # fh.write(data)
          # fh.close

          MdcReportImage.create(mdc_report: rep, url: "#{url}/#{filename}", path: "#{cpath}/#{filename}")

        end
        rep.update(description: "#{rep.description}\n#{rpath}")
      end

      @results = get_filter

      respond_to do |format|
        format.html {render 'mdc/report_index'}
        format.js {render partial: 'mdc/create_report_js'}
      end
    rescue Exception => e
      @error = e.message+"\n"+e.backtrace.join("\n")
      respond_to do |format|
        format.js {render partial: 'layouts/error'}
      end
    end
  end

  def codes
    render 'mdc/codes_index'
  end

  def create_user
    u = params.require(:user)
    a = params.require(:activation_code) unless params[:activation_code] == ''
    person = nil
    if MdcUser.find_by(user: u).nil? and params[:activation_code] != ''
      # Person.mdc.each do |p|
      #   if p.mdc_user == u.downcase
      #     person = p
      #     break
      #   end
      # end
      MdcUser.create(:user => params.require(:user).upcase, :activation_code => params.require(:activation_code), :assigned_to_person => person )
    end
    render 'mdc/codes_index'
  end

  def update_user
    unless @code.nil?
      case @action
      when :edit
        if @holder.class == Person
          @holder.rearrange_mdc_users @code.user
          @code.update(activation_code: params.require(:mdc_activation_code), assigned_to_person: @holder, assigned_to_company: nil)
        elsif @holder.class == Company
          p = Person.find_by_mdc_user(@code.user)
          p.rearrange_mdc_users nil unless p.nil?
          @code.update(activation_code: params.require(:mdc_activation_code), assigned_to_company: @holder, assigned_to_person: nil)
        end
      when :delete
        @code.destroy
      end
      # @msg = 'Codice creato.'
    else
      # @msg = 'Codice esistente.'
    end
    respond_to do |format|
      format.js { render :partial => 'mdc/users_list_js' }
    end
  end

  def close_fare
    begin
      mdc = MdcWebservice.new
      mdc.begin_transaction
      mdc.update_data_collection_rows_status(Base64.decode64(params.require(:data_collection_rows)))
      mdc.delete_tabgen_by_selector([TabgenSelector.new({tabname: 'FARES', index: 0, value: params.require(:id), deviceCode: ''})])
      # Person.mdc.each do |p|
      #   mdc.send_push_notification([p.mdc_user],'Aggiornamento viaggi.')
      # end
      mdc.send_same_push_notification_ext(MdcUser.assigned.to_a,'Chiusura viaggio.')
      # MdcUser.assigned.each do |mdcu|
      #   mdc.send_push_notification_ext([mdcu],'Aggiornamento viaggi.',nil)
      # end
      # mdc.send_push_notification(['ALL'],'Aggiornamento viaggi.')
      # mdc.send_push_notification(Person.mdc.pluck(:mdc_user),'Aggiornamento viaggi.')
      mdc.commit_transaction
      mdc.end_transaction
      # @status = 0
    rescue Exception => e
      @error = e.message+"\n"+e.backtrace.join("\n")
      respond_to do |format|
        format.js {render partial: 'layouts/error'}
      end
    end

    @mdc_user = MdcUser.find_by(user: params.require(:user_id))
    @result = mdc.get_fares_data({applicationID: 'FARES', deviceCode: @mdc_user.user.upcase, status: 0})#.reverse[0,10]

    mdc.close_session


    @mdc_user.update(open_documents: @result.count)

    respond_to do |format|
      # format.js { render partial: 'mdc/index_part_js' }
      format.html { render 'mdc/index' }
    end
  end

  def self.update_plates

    mdc = MdcWebservice.new
    mdc.begin_transaction
    # tb = mdc.select_tabgen(Tabgen.new({deviceCode: "All user", key: '', order: 0, tabname: 'VEHICLES_TMP'}))
    
    mdc.delete_tabgen_by_selector([TabgenSelector.new({tabname: 'RUNNING_VEHICLES', index: 0, value: '%', deviceCode: ""})])
    mdc.commit_transaction
    Vehicle.where(dismissed: false).where("property_id = #{Company.chiarcosso.id} or property_id = #{Company.transest.id}").reject{ |v| v.plate.nil? }.to_a.each do |v|

      # mdc.insert_or_update_tabgen(Tabgen.new({deviceCode: "|#{MdcUser.all.map{|mu| mu.user.upcase}.join('|')}|", key: v.id, order: 0, tabname: 'VEHICLES', values: [v.plate,v.vehicle_type.name]}))
       mdc.insert_or_update_tabgen(Tabgen.new({deviceCode: "__ALL__", key: v.id, order: 0, tabname: 'RUNNING_VEHICLES', values: [v.plate,v.vehicle_type.name]}))
      puts "#{v.id}:  #{v.plate} has been uploaded"
    end
    # mdc.send_same_push_notification_ext((MdcUser.assigned.to_a),'Aggiornamento veicoli.')
    mdc.commit_transaction
    mdc.end_transaction
    mdc.close_session

  end

  def update_fares
    # user = Person.find_by_complete_name(Base64.decode64(params.require(:driver)))
    user = MdcUser.find_by_holder(Base64.decode64(params.require(:driver))) || MdcUser.find_by_holder(Base64.decode64(params.require(:company)))
    unless user.nil?
      if user.assigned_to_person.nil? and user.assigned_to_company.nil?
        @msg = "Messaggio non inviato. Targa: #{params[:VehiclePlateNumber]}, #{user.holder.complete_name} non ha un utente assegnato."
      else

        msg = Base64.decode64(params.require('ChatMessage')).force_encoding(Encoding::UTF_8)
        sync_fares_table(
          msg: msg,
          id: params.require(:id),
          user: user
        )
        @msg = "Messaggio inviato. Targa: #{params[:VehiclePlateNumber]}, #{user.holder.complete_name} (utente: #{user.user})."
      end
    else
      @msg = "Messaggio non inviato. Targa: #{params[:VehiclePlateNumber]}, #{Base64.decode64(params.require(:driver))} o #{Base64.decode64(params.require(:company))}non esistono."
    end

    render :partial => 'layouts/messages'
  end

  # Update FARES tabgen, send push notifications
  def self.sync_fares_table(opts)

    opts[:msg] = HTMLEntities.new.encode(opts[:msg].force_encoding("ISO8859-1"))
    mdc = MdcWebservice.new
    mdc.begin_transaction
    mdc.delete_tabgen_by_selector([TabgenSelector.new({tabname: 'FARES', index: 0, value: opts[:id], deviceCode: ''})])
    mdc.insert_or_update_tabgen(Tabgen.new({deviceCode: "|#{opts[:user].user.upcase}|", key: opts[:id], order: 0, tabname: 'FARES', values: [opts[:msg]]}))
    # Person.mdc.each do |p|
    #   mdc.send_push_notification([p.mdc_user],'Aggiornamento viaggi.') unless p == driver
    # end
    # MdcUser.all.each do |p|
    #   mdc.send_push_notification([p.user],'Aggiornamento viaggi.') unless p == user
    # end
    # mdc.send_push_notification((MdcUser.all - [user]),'Aggiornamento viaggi.')
    # mdc.send_push_notification([user],msg)
    # MdcUser.assigned.each do |mdcu|
    #   mdc.send_push_notification_ext([mdcu],'Aggiornamento viaggi.',nil) unless mdcu == user
    # end
    mdc.send_same_push_notification_ext((MdcUser.assigned.to_a - [opts[:user]]),'Aggiornamento viaggi.')
    mdc.send_push_notification_ext([opts[:user]],opts[:msg],nil)
    mdc.commit_transaction
    mdc.end_transaction
    mdc.close_session
  end

  def sync_fares_table(opts)

    WsController.sync_fares_table(opts)
  end

  # Query MSSQL for new fares, eventually send them to the mdc app and mark its mdc check on MSSQL
  def self.send_fares_massive

    # Prepare client and query
    c = MssqlReference.get_client
    q = <<-QUERY
      select distinct
        IDPosizione,
        a.nominativo as driver,
        g.mdc,
        d.RagioneSociale as company,
        (
          convert(nvarchar,g.data,104)+
          +' '+
          +m.Targa+
          +' - '+
          +COALESCE(r.Targa,'')+
          +' '+
          +a.nominativo+
          +'\r\n'+
          +convert(nvarchar,g.ProgressivoGiornata)+
          +' - Partenza: '+
          +COALESCE(p.Descrizione,
            COALESCE(cc.[ditta partenza],'')+
            +' '+
            +COALESCE(cc.[via partenza],'')+
            +' '+
            +COALESCE(cc.[cap partenza],'')+
            +' '+
            +COALESCE(cc.partenza,g.partenza)+
            +' '+
            +COALESCE(cc.[provincia partenza],g.Pv)
          )

          +' - Merce: '+
          +COALESCE(ma.merce,mg.merce)+
          +' '+
          +COALESCE(cc.[Descrivi Merce],'')+
          +' '+
          +' - Destinazione: '+
          +COALESCE(cc.[ditta arrivo],'')+
          +' '+
          +COALESCE(cc.[via arrivo],'')+
          +' '+
          +COALESCE(cc.[cap arrivo],'')+
          +' '+
          +COALESCE(cc.[arrivo],g.Destinazione)+
          +' '+
          +COALESCE(cc.[provincia arrivo],g.Pr)+
          +' '+
          +COALESCE(cc.note,'')+
          +' '+
          +COALESCE(g.RifCliente,'')
        ) as msg

      from giornale g

      left join autisti a ON g.idAutista = a.IDAutista
      left join [calcolo costi] cc ON g.idviaggi = cc.idviaggi
      left join materiali ma ON ma.idmerce = cc.merce
      left join materiali mg ON mg.idmerce = g.merce
      left join veicoli m ON g.idtarga = m.idveicolo
      left join rimorchi1 r ON g.idrimorchi = r.idrimorchio
      left join clienti co ON cc.cliente = co.idcliente
      left join clienti c ON g.idcliente = c.idcliente
      left join clienti d ON a.idFornitore = d.CodTraffico
      left join piazzali p ON g.IDPiazzaleSgancio = p.IDPiazzale

      where
        g.Data = "#{Time.now.strftime("%Y%m%d")}"
      and
        g.mdc != 1
      and
        g.ProgressivoGiornata between 1 and 9
      and
        g.IDCliente not in (9996,10336,9995,9997,9998,9985,10629,10630,10631,10632,9986,9989,2265,9994,9999);
    QUERY

    # Get fares
    fares = c.execute(q)

    # Log found trips
    special_logger.info("\r\n-------------------- Timely check: #{fares.count} trips found -------------------------\r\n")
    logistics_logger.info("\r\n-------------------- Timely check: #{fares.count} trips found -------------------------\r\n") unless Rails.env == 'development'

    # Loop through trips and send the ones that have a valid MDC user
    sent = 0
    fares.each do |fare|
      begin

        # Find user
        matches = fare['driver'].match(/\.([A-Z ]*)? (.*)/)

        if matches.nil? || matches[2].nil?
          driver = fare['driver']
        else
          driver = matches[2]
        end
        user = MdcUser.find_by_holder(driver) || MdcUser.find_by_holder(fare['company'])

        if user.nil?

          special_logger.info("[ #{fare['IDPosizione']} ] -- Trip discarded: #{fare['msg']}")
          logistics_logger.info("[ #{fare['IDPosizione']} ] -- Trip discarded: #{fare['msg']}") unless Rails.env == 'development'
          next
        end

        # Update table
        self.sync_fares_table(
          msg: fare['msg'],
          id: fare['IDPosizione'],
          user: user
        )

        #Set mdc flag in mssql
        MssqlReference.get_client.execute("update giornale set mdc = -1 where IDPosizione = #{fare['IDPosizione']}")

        sent += 1
        special_logger.info("\n\n[ #{fare['IDPosizione']} ] -- Trip sent (#{user.holder.complete_name}): #{fare['msg']}\n\n")
        logistics_logger.info("\n\n[ #{fare['IDPosizione']} ] -- Trip sent (#{user.holder.complete_name}): #{fare['msg']}\n\n") unless Rails.env == 'development'

      rescue Exception => e

        special_logger.error("\r\n#{fare.inspect}\r\n\r\n#{e.message}\r\n")
        logistics_logger.error("\r\n#{fare.inspect}\r\n\r\n#{e.message}\r\n") unless Rails.env == 'development'
        next
      end
    end

    special_logger.info("\r\n----------------------- #{sent} trips sent ----------------------------\r\n")
    logistics_logger.info("\r\n----------------------- #{sent} trips sent ----------------------------\r\n") unless Rails.env == 'development'

  end

  def print_pdf
    photos = Array.new
    mdc = MdcWebservice.new
    params.require(:photos).each do |p|
      # p.sub!('http://chiarcosso.mobiledatacollection.it/','/var/lib/tomcat8/webapps/')
      # p.sub!('http://outpost.chiarcosso/','/var/lib/tomcat8/webapps/')
      p.sub!("http://#{ENV['RAILS_MDC_ADDRESS']}/",'/var/lib/tomcat8/webapps/')

      f = mdc.download_file(p).body[/Content-Type: image\/jpeg.*?\r\n\r\n(.*?)\r\n--MIMEBoundary/m,1]
      # photos << f.force_encoding("utf-8") unless f.nil?
      photos << f unless f.nil?
    end
    margins = 15
    pdf = Prawn::Document.new :filename=>'foo.pdf',
                          :page_size=> "A4",
                          :margin => margins

    photos.each do |p|
      file = File.open('tmp.jpg','wb')
      file.write(p)
      file.close
      size = FastImage::size('tmp.jpg')

      unless size.nil?
        if size[0] > size[1]
            image = MiniMagick::Image.new("tmp.jpg")
            image.rotate(-90)
        end
      end
      pdf.image 'tmp.jpg', :fit => [595.28 - margins*2, 841.89 - margins*2]
    end
    mdc.close_session
    respond_to do |format|
      format.pdf do
        send_data pdf.render,
        filename: "#{params[:id]} #{params[:driver]}",
        type: "application/pdf"
      end
    end
  end

  private

  def set_status
    if params[:status] == 'opened' or params[:status].nil?
      @status = 0
    else
      @status = 1
    end
  end

  def get_holder
    if params.require(:holder_type) == 'Person'
      @holder = Person.find_by_complete_name(params.require(:holder))
    elsif params.require(:holder_type) == 'Company'
      @holder = Company.find_by_name(params.require(:holder))
    end
  end

  def get_filter

    # Build filter from params and run the resulting query
    @office = params.require(:office)

    return Array.new if @office.nil?

    if params[:reports].nil?
      # First call, no params, set filter to default
      p = get_filter_defaults
    else
      # Filter call, set filter to params
      p = params.require('reports').permit(:managed, :date_from, :date_to, :search, :types => [])
    end

    # Filter already managed
    @managed = !p[:managed].nil?

    # Set dates
    Time.zone = 'Europe/Rome'
    date_to = Time.zone.strptime(p[:date_to]+' 23:59:59',"%Y-%m-%d %H:%M:%S")
    date_from = Time.zone.strptime(p[:date_from]+' 00:00:00',"%Y-%m-%d %H:%M:%S")
    @date_to = Date.strptime(p[:date_to],"%Y-%m-%d")
    @date_from = Date.strptime(p[:date_from],"%Y-%m-%d")

    # Set search
    @search = p[:search].to_s.tr("'","''")[0..255]

    # Set correct types
    @types = {
      'anomalia_sede': false,
      'attrezzatura': false,
      'contravvenzione': false,
      'dpi': false,
      'furto': false,
      'guasto': false,
      'incidente': false,
      'infortunio': false,
      'sosta_prolungata': false
    }

    p[:types].each do |t|
      @types[t] = true
    end

    # Set up search to look in vehicles plates, drivers names, a report descriptions
    if @search == ''

      # Run query
      res = MdcReport.where("sent_at between '#{date_from.in_time_zone('UTC').strftime("%Y-%m-%d %H:%M:%S")}' and '#{date_to.in_time_zone('UTC').strftime("%Y-%m-%d %H:%M:%S")}'")
              .where("#{@office} = 1")
              .where("#{@managed ? "1 = 1" : "managed_at is null"}")
              .where("report_type in (#{@types.select{ |k,t| t }.map{ |k,t| "'#{k}'"}.join(',')})")
              .order(sent_at: :desc)

    else
      w = <<-SEARCH
          vehicle_id in
            (select v.id from vehicles v
              inner join vehicle_informations vi on vi.vehicle_id = v.id
              where vi.information like ? and vi.vehicle_information_type_id = #{VehicleInformationType.plate.id}
            )
          or mdc_reports.description like ?
          or mdc_reports.mdc_user_id in
            (select mdcu.id from mdc_users mdcu
              inner join people p on p.id = mdcu.assigned_to_person_id
              where (concat(p.name,' ',p.surname) like ? or concat(p.surname,' ',p.name) like ?)
            )
      SEARCH

      # Run query
      res = MdcReport.where("sent_at between '#{date_from.in_time_zone('UTC').strftime("%Y-%m-%d %H:%M:%S")}' and '#{date_to.in_time_zone('UTC').strftime("%Y-%m-%d %H:%M:%S")}'")
              .where("#{@office} = 1")
              .where("#{@managed ? "1 = 1" : "managed_at is null"}")
              .where("report_type in (#{@types.select{ |k,t| t }.map{ |k,t| "'#{k}'"}.join(',')})")
              .where(w,"%#{@search}%","%#{@search}%","%#{@search}%","%#{@search}%")
              .order(sent_at: :desc)
    end
    unmanaged = current_user.new_mdc_reports_for_office(@office)
    @new_entries_message = "Ci segnalazioni non gestite.\r\n#{unmanaged.map{ |u| "#{u.sent_at.strftime("%d/%m/%Y")} -- #{u.description}" }.join("\r\n")}" if unmanaged.count > 0
    return res
  end

  # Set defaults for report filter
  def get_filter_defaults(office = nil)

    office = @office if office.nil?

    case office
    when 'maintenance' then
      p = {types: ['anomalia_sede','attrezzatura','contravvenzione','furto','guasto','incidente']}
    when 'logistics' then
      p = {types: ['attrezzatura','contravvenzione','dpi','furto','sosta_prolungata','incidente','infortunio']}
    when 'hr' then
      p = {types: ['dpi','furto','incidente','infortunio']}
    end

    p[:date_from] = (Time.now - 48.hours).strftime("%Y-%m-%d")
    p[:date_to] = Time.now.strftime("%Y-%m-%d")

    return p
  end

  def self.get_filter_defaults_by_office office
    get_filter_defaults office
  end

  def get_action
    unless params[:id].nil?
      @code = MdcUser.find(params.require(:id).to_i)
    end
    case params.permit(:commit)[:commit]
    when 'Modifica'
        @action = :edit
      when 'Elimina'
        @action = :delete
    end
  end

  def report_params

    res = params.require(:notification).permit(:description, :vehicle_plate, :type, :driver_name, :hq, :photos => [])
    person = res[:driver_name].nil? || res[:driver_name] == '' ? current_user.person : Person.find_by_complete_name(res[:driver_name])
    res[:type] = 'anomalia_sede' if res[:type].nil?

    report = {
      description: res[:description],
      vehicle: res[:vehicle_plate].nil? ? nil : Vehicle.find_by_plate(res[:vehicle_plate]),
      report_type: res[:type],
      person: person,
      sent_at: Time.now,
      hq: ((res[:hq].nil? && res[:type] != 'anomalia_sede') ? false : true),
      hr: MdcReport.offices(res[:type]).include?(:hr),
      maintenance: MdcReport.offices(res[:type]).include?(:maintenance),
      logistics: MdcReport.offices(res[:type]).include?(:logistics),
      user: current_user
    }

    return {report: report, photos: res[:photos]}
  end

  def self.logistics_logger
    @@logistics_logger ||= Logger.new("/mnt/wshare/Traffico/log_mdc/fares.log")
  end

  def self.special_logger
    @@fares_logger ||= Logger.new("#{Rails.root}/log/fares.log")
  end
end
