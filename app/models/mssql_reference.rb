class MssqlReference < ApplicationRecord
  resourcify
  require 'tiny_tds'


  belongs_to :local_object, polymorphic: true

  scope :identify, ->(local_object, table, id) { where(local_object: local_object, remote_object_table: table, remote_object_id: id).first }


  def self.update_all
    upsync_vehicles
    upsync_trailers
    upsync_other_vehicles
    upsync_employees
    # update_employees
    # update_companies
  end

  def self.upsync_vehicles(update)
    vbase = VehiclesController.helpers.get_vehicle_basis
    begin
      special_logger.info("Starting vehicles upsync") if update
      @response = "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Inizio importazione #{(update ? '' : '(simulata)')}\n"
      client = get_client

      @vehicles = Array.new
      @errors = Array.new
      response = ''
      query = "select distinct 'Veicoli' as table_name, idveicolo as id, targa as plate, telaio as chassis, "\
                  "Tipo.Tipodiveicolo as type, ditta as property, marca as manufacturer, "\
                  "modello as model, modello2 as registration_model, codice_lavaggio as carwash_code, "\
                  "circola as notdismissed, tipologia.[tipologia semirimorchio] as typology, KmAttuali as mileage, "\
                  "ISNULL(convert(nvarchar, data_immatricolazione,126),convert(nvarchar,ISNULL(anno,1900))+'-01-01') as registration_date, categoria as category, motivo_fuori_parco "\
                  "from veicoli "\
                  "left join Tipo on veicoli.IDTipo = Tipo.IDTipo "\
                  "left join [Tipologia rimorchio/semirimorchio] tipologia on veicoli.Id_Tipologia = tipologia.ID "\
                  "where marca is not null and marca != '' and modello is not null and modello != '' "\
                  "and ditta is not null and ditta != '' and marca != 'Targa' and targa is not null and targa != '' "\
                  "order by targa"
      list = client.execute(query)

      special_logger.info("#{list.count} records found")
      special_logger.info(query)
      response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Trovati #{list.count} record nella tabella Veicoli, dove targa, marca, modello e ditta sono compilati.\n"
      list.each do |r|
        response += VehiclesController.helpers.create_vehicle_from_veicoli(r,update,vbase)
      end
    rescue Exception => e
      special_logger.error("#{e.message}\n#{e.backtrace}")
      response += "<span class=\"error-line\">#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - #{e.message}\n#{e.backtrace}</span>\n"

    end

    return {response: response, array: [] }
  end

  def self.upsync_external_vehicles(update)
    vbase = VehiclesController.helpers.get_vehicle_basis
    begin
      special_logger.info("Starting external vehicles upsync") if update
      response = "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Inizio importazione #{(update ? '' : '(simulata)')}\n"
      client = get_client

      @vehicles = Array.new
      @errors = Array.new
      response = ''
      query = "select distinct 'Veicoli' as table_name, idveicolo as id, idfornitore, targa as plate, "\
                  "Tipo.Tipodiveicolo as type, clienti.ragionesociale as owner, veicoli.idfornitore "\
                  "from veicoli "\
                  "inner join clienti on veicoli.IDfornitore = clienti.codtraffico "\
                  "left join Tipo on veicoli.IDTipo = Tipo.IDTipo "\
                  "where (ditta is null or ditta = '') and idfornitore is not null and idfornitore != '' "\
              "union select distinct 'Rimorchi1' as table_name, idrimorchio as id, idfornitore, targa as plate, "\
                  "(case tipo when 'S' then 'Semirimorchio' when 'R' then 'Rimorchio' end) as type, "\
                  "clienti.ragionesociale as owner, rimorchi1.idfornitore "\
                  "from rimorchi1 "\
                  "inner join clienti on rimorchi1.Idfornitore = clienti.codtraffico "\
                  "where (ditta is null or ditta = '') and idfornitore is not null and idfornitore != '' "\
                  "and targa is not null and targa != '' "\
                  "order by targa"
      list = client.execute(query)

      special_logger.info("#{list.count} records found")
      special_logger.info(query)
      response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Trovati #{list.count} record nella tabella Veicoli Rimorchi1, dove targa e fornitore sono compilati e ditta non lo è.\n"
      list.each do |r|
        response += VehiclesController.helpers.create_external_vehicle_from_veicoli(r,update,vbase)
      end
    rescue Exception => e
      special_logger.error("#{e.message}\n#{e.backtrace}")
      response += "<span class=\"error-line\">#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - #{e.message}\n#{e.backtrace}</span>\n"

    end

    return {response: response, array: [] }
  end

  def self.upsync_trailers(update)
    vbase = VehiclesController.helpers.get_vehicle_basis
    begin
      special_logger.info("Starting trailers upsync") if update
      response = "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Inizio importazione #{(update ? '' : '(simulata)')}\n"
      client = get_client
      plate = VehicleInformationType.plate
      chassis = VehicleInformationType.chassis
      atc = Company.chiarcosso
      te = Company.transest
      motivo_fuori_parco = VehicleInformationType.find_by(name: 'Motivo fuori parco')
      motivo_fuori_parco = VehicleInformationType.create(name: 'Motivo fuori parco') if motivo_fuori_parco.nil?
      @vehicles = Array.new
      @errors = Array.new
      query = "select 'Rimorchi1' as table_name, idrimorchio as id, targa as plate, telaio as chassis, "\
                  "(case Tipo when 'S' then 'Semirimorchio' when 'R' then 'Rimorchio' end) as type, ditta as property, "\
                  "marca as manufacturer, (case Tipo when 'S' then 'Semirimorchio' when 'R' then 'Rimorchio' end) as model, "\
                  "(case Tipo when 'S' then 'Semirimorchio' when 'R' then 'Rimorchio' end) as registration_model, "\
                  "codice_lavaggio as carwash_code, circola as notdismissed, "\
                  "tipologia.[tipologia semirimorchio] as typology, Km as mileage, "\
                  "ISNULL(convert(nvarchar, data_immatricolazione,126),convert(nvarchar,ISNULL(anno,1900))+'-01-01') as registration_date, "\
                  "categoria as category, motivo_fuori_parco "\
                  "from rimorchi1 "\
                  "left join [Tipologia rimorchio/semirimorchio] tipologia on rimorchi1.[Tipologia Rimonchio/Semirimorchio] = tipologia.ID "\
                  "where marca is not null and marca != '' and tipo is not null and tipo != '' "\
                  "and ditta is not null and ditta != '' and marca != 'Targa' and targa is not null and targa != '' "\
                  "order by targa"
      list = client.execute(query)

      special_logger.info("#{list.count} records found")
      special_logger.info(query)
      response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Trovati #{list.count} record nella tabella Rimorchi1, dove targa, marca, tipo e ditta sono compilati.\n"
      list.each do |r|
        response += VehiclesController.helpers.create_vehicle_from_veicoli(r,update,vbase)
      end
    rescue Exception => e
      special_logger.error("#{e.message}\n#{e.backtrace}")
      response += "<span class=\"error-line\">#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - #{e.message}\n#{e.backtrace}</span>\n"

    end

    return {response: response, array: [] }
  end

  def self.upsync_other_vehicles(update)
    vbase = VehiclesController.helpers.get_vehicle_basis
    begin
      special_logger.info("Starting other_vehicles upsync") if update
      response = "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Inizio importazione #{(update ? '' : '(simulata)')}\n"
      client = get_client
      plate = VehicleInformationType.plate
      chassis = VehicleInformationType.chassis
      atc = Company.chiarcosso
      te = Company.transest
      ec = Company.edilizia
      motivo_fuori_parco = VehicleInformationType.find_by(name: 'Motivo fuori parco')
      motivo_fuori_parco = VehicleInformationType.create(name: 'Motivo fuori parco') if motivo_fuori_parco.nil?
      posti_a_sedere = VehicleInformationType.find_by(name: 'Posti a sedere')
      posti_a_sedere = VehicleInformationType.find_by(name: 'Posti a sedere') if posti_a_sedere.nil?
      @vehicles = Array.new
      @errors = Array.new
      query = "select 'Altri mezzi' as table_name, convert(int,cod) as id, targa as plate, telaio as chassis, "\
                  "tipo.tipodiveicolo as type, ditta as property, numero_posti as posti_a_sedere, "\
                  "marca as manufacturer, modello as model, modello as registration_model, "\
                  "codice_lavaggio as carwash_code, circola as notdismissed, "\
                  "tipologia.[tipologia semirimorchio] as typology, Km as mileage, "\
                  "ISNULL(convert(nvarchar, data_immatricolazione,126),convert(nvarchar,ISNULL(anno,1900))+'-01-01') as registration_date, "\
                  "categoria as category, motivo_fuori_parco "\
                  "from [Altri mezzi] "\
                  "left join Tipo on Tipo.IDTipo = [Altri mezzi].id_tipo "\
                  "left join [Tipologia rimorchio/semirimorchio] tipologia on [Altri mezzi].id_tipologia = tipologia.ID "\
                  "where marca is not null and marca != '' and tipo is not null and tipo != '' "\
                  "and ditta is not null and ditta != '' and marca != 'Targa' and modello is not null and modello != '' and targa is not null and targa != '' "\
                  "order by targa"
      list = client.execute(query)

      special_logger.info("#{list.count} records found")
      special_logger.info(query)
      response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Trovati #{list.count} record nella tabella Altri mezzi, dove targa, marca, modello, tipo e ditta sono compilati.\n"
      list.each do |r|
        response += VehiclesController.helpers.create_vehicle_from_veicoli(r,update,vbase)
      end
    rescue Exception => e
      special_logger.error("#{e.message}\n#{e.backtrace}")
      response += "<span class=\"error-line\">#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - #{e.message}\n#{e.backtrace}</span>\n"

    end

    return {response: response, array: [] }
  end

  def self.upsync_employees(update)

    begin
      special_logger.info("Starting vehicles upsync") if update
      response = "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Inizio importazione #{(update ? '' : '(simulata)')}\n"
      client = get_client

      atc = Company.chiarcosso
      te = Company.transest
      driver = CompanyRelation.find_by(name: 'Autista')
      driver = CompanyRelation.create(name: 'Autista') if driver.nil?

      @errors = Array.new
      query = "select 'Autisti' as table_name, a.Idautista as id, a.ditta as employer, a.nome as name, a.cognome as surname, "\
                  "Mansione.Descrizione as role, a.attivo as dismissed "\
                  "from Autisti a "\
                  "left join Mansione on a.idmansione = mansione.idmansione "\
                  "where a.ditta is not null and a.ditta != '' and a.nome is not null and a.nome != '' "\
                  "and a.cognome is not null and a.cognome != ''"\
                  "order by a.cognome,a.nome"
      list = client.execute(query)

      special_logger.info("#{list.count} records found")
      special_logger.info(query)
      response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - Trovati #{list.count} record nella tabella Autisti, dove ditta, nome e cognome sono compilati.\n"
      list.each do |r|
        @error = nil

        employer = atc if r['employer'] == 'A'
        employer = te if r['employer'] == 'T'
        r['name'] = r['name'].strip.titleize
        r['surname'] = r['surname'].strip.titleize

        if employer.nil?
          @error = " #{r['cognome']} #{r['nome']} (#{r['id']}) - Invalid employer: #{r['employer']}"
          response += "<span class=\"error-line\">#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{r['cognome']} #{r['nome']} (#{r['id']}) - Ditta non valida: #{r['employer']}</span>\n"
          special_logger.error(@error)
        end
        if r['notdismissed'] == false
          notdismissed = false
        else
          notdismissed = true
        end

        company_relation = CompanyRelation.find_by(:name => r['role'])
        if company_relation.nil?
          @error = " #{r['cognome']} #{r['nome']} (#{r['id']}) - Invalid company relation: #{r['role']}"
          response += "<span class=\"error-line\">#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")}  #{r['cognome']} #{r['nome']} (#{r['id']}) - Mansione non valida: #{r['role']}</span>\n"
          special_logger.error(@error)
        end

        p = Person.find_by(name: r['name'], surname: r['surname'])

        begin
          if @error.nil?
            if p.nil?
              if update
                p = Person.create(name: r['name'], surname: r['surname'])
              else
                p = Person.new(name: r['name'], surname: r['surname'])
                p.id = 0
              end

              special_logger.info(" - #{p.id} ->  #{r['cognome']} #{r['nome']} (#{r['id']}) - Created (id: #{p.id}).")
              response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")}  #{r['cognome']} #{r['nome']} (#{r['id']}) - Creato (id: #{p.id}).\n"
              special_logger.info("name: #{p.surname} #{p.name}.")
              response += "nome: #{p.name}, cognome: #{p.surname}.\n"

              CompanyPerson.create(person: p, company: employer, company_relation: company_relation, acting: notdismissed) if update
              special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - CompanyPerson added -> #{employer}: #{r['role']} (id: #{p.id}).")
              response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunto ruolo -> #{employer}: #{r['role']} (id: #{p.id}).\n"

              if company_relation == driver
                cwc = CarwashDriverCode.createUnique p if update
                response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunta tessera lavaggio: #{cwc.to_s}.\n"
                special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - Carwash code added: #{cwc.to_s}.")
              end

              mssqlref = MssqlReference.create(local_object: p, remote_object_table: 'Autisti', remote_object_id: r['id'].to_i) if update
              response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunto riferimento MSSQL: #{mssqlref.to_s}.\n"
              special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - MSSQL reference added: #{mssqlref.to_s}.")

            elsif p.check_properties(r)

              response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:S")} #{p.surname} #{p.name} (#{r['id']}) - A posto (id: #{p.id}).\n"
              unless p.has_relation?(employer,company_relation)
                CompanyPerson.create(person: p, company: employer, company_relation: company_relation, acting: notdismissed) if update
                special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - CompanyPerson added -> #{employer}: #{r['role']} -> #{notdismissed ? 'acting' : 'non acting'} (id: #{p.id}).")
                response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunto ruolo -> #{employer}: #{r['role']} -> #{notdismissed ? 'attivo' : 'non attivo'} (id: #{p.id}).\n"
              else
                cr = CompanyPerson.find_by(person: p, company: employer, company_relation: company_relation)
                if cr.acting != notdismissed
                  cr.update(acting: notdismissed) if update
                  special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - CompanyPerson updated -> #{employer}: #{r['role']} -> #{notdismissed ? 'acting' : 'non acting'} (id: #{p.id}).")
                  response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunto ruolo -> #{employer}: #{r['role']} -> #{notdismissed ? 'attivo' : 'non attivo'} (id: #{p.id}).\n"
                end
              end
              if company_relation == driver
                if p.carwash_driver_code.nil?
                  cwc = CarwashDriverCode.createUnique p if update
                  response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunta tessera lavaggio: #{cwc.to_s}.\n"
                  special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - Carwash code added: #{cwc.to_s}.")
                end
              end
              unless p.has_reference?('Autisti',r['id'])
                mssqlref = MssqlReference.create(local_object: p, remote_object_table: 'Autisti', remote_object_id: r['id'].to_i) if update
                response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunto riferimento MSSQL: #{mssqlref.to_s}.\n"
                special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - MSSQL reference added: #{mssqlref.to_s}.")
              end

            else
              p.update(name: r['name'], surname: r['surname']) if update
              special_logger.info(" - #{p.id} ->  #{r['cognome']} #{r['nome']} (#{r['id']}) - Created (id: #{p.id}).")
              response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")}  #{r['cognome']} #{r['nome']} (#{r['id']}) - Creato (id: #{p.id}).\n"
              special_logger.info("name: #{p.surname} #{p.name}.")
              response += "nome: #{p.name}, cognome: #{p.surname}.\n"

              unless p.has_relation?(employer,company_relation)
                CompanyPerson.create(person: p, company: employer, company_relation: company_relation, acting: notdismissed) if update
                special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - CompanyPerson added -> #{employer}: #{r['role']} -> #{notdismissed ? 'acting' : 'non acting'} (id: #{p.id}).")
                response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunto ruolo -> #{employer}: #{r['role']} -> #{notdismissed ? 'attivo' : 'non attivo'} (id: #{p.id}).\n"
              else
                cr = CompanyPerson.find_by(person: p, company: employer, company_relation: company_relation)
                if cr.acting != notdismissed
                  cr.update(acting: notdismissed) if update
                  special_logger.info(" - #{p.id} -> #{p.surname} #{p.name} (#{r['id']}) - CompanyPerson updated -> #{employer}: #{r['role']} -> #{notdismissed ? 'acting' : 'non acting'} (id: #{p.id}).")
                  response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunto ruolo -> #{employer}: #{r['role']} -> #{notdismissed ? 'attivo' : 'non attivo'} (id: #{p.id}).\n"
                end
              end
              if company_relation == driver
                cwc = CarwashDriverCode.createUnique p if update
                response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{p.surname} #{p.name} (#{r['id']}) - Aggiunta tessera lavaggio: #{cwc.to_s}.\n"
                special_logger.info(" - #{v.id} -> #{p.surname} #{p.name} (#{r['id']}) - Carwash code added: #{cwc.to_s}.")
              end
              unless p.has_reference?('Autisti',r['id'])
                mssqlref = MssqlReference.create(local_object: p, remote_object_table: 'Autisti', remote_object_id: r['id'].to_i) if update
                response += "#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} #{r['cognome']} #{r['nome']} (#{r['id']}) - Aggiunto riferimento MSSQL: #{mssqlref.to_s}.\n"
                special_logger.info(" - #{p.id} -> #{r['cognome']} #{r['nome']} (#{r['id']}) - MSSQL reference added: #{mssqlref.to_s}.")
              end
            end
          end
        rescue Exception => e
          special_logger.error("  - #{r['plate']} (#{r['id']}) #{e.message}\n#{e.backtrace}")
          response += "<span class=\"error-line\">#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} -  -> #{r['plate']} (#{r['id']}) #{e.message}\n#{e.backtrace}</span>\n"

        end
      end
    rescue Exception => e
      special_logger.error("#{e.message}\n#{e.backtrace}")
      response += "<span class=\"error-line\">#{DateTime.current.strftime("%d/%m/%Y %H:%M:%S")} - #{e.message}\n#{e.backtrace}</span>\n"

    end

    return {response: response, array: [] }
  end

  def to_s
    "id: #{self.id}, local_object_id: #{self.local_object_id}, local_object_type: #{self.local_object_type}, remote_object_id: #{self.remote_object_id}, remote_object_table: #{self.remote_object_table}"
  end

  def self.get_client
    TinyTds::Client.new username: ENV['RAILS_MSSQL_USER'], password: ENV['RAILS_MSSQL_PASS'], host: ENV['RAILS_MSSQL_HOST'], port: ENV['RAILS_MSSQL_PORT'], database: ENV['RAILS_MSSQL_DB']
  end

  def self.id_for table
    case table
      when 'Veicoli' then 'Idveicolo'
      when 'Altri mezzi' then 'COD'
      when 'Rimorchi1' then 'IdRimorchio'
      when "Autisti" then 'Idautista'
    end
  end

  private

  def self.special_logger
    @@mssql_reference_logger ||= Logger.new("#{Rails.root}/log/mssql_reference.log")
  end

end
