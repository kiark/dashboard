class Person < ApplicationRecord
  resourcify

  has_many :relations, class_name: 'CompanyPerson', :dependent => :delete_all
  has_many :companies, through: :relations
  has_many :company_relations, through: :relations

  has_many :prepaid_cards
  has_many :badge_assignments, :dependent => :destroy
  has_many :badges, through: :badge_assignments
  has_many :presence_timestamps, through: :badges
  has_many :working_schedules, :dependent => :destroy
  has_many :presence_records
  has_many :granted_leaves, class_name: 'GrantedLeave'
  has_many :item_relations, :dependent => :destroy
  has_many :items, through: :item_relations

  has_one :carwash_driver_code, :dependent => :destroy
  has_many :mssql_references, as: :local_object, dependent: :destroy
  has_many :vehicle_properties, as: :owner

  scope :order_alpha, -> { order(:name).order(:surname) }
  scope :order_alpha_surname, -> { order(:surname).order(:name) }
  # scope :find_by_complete_name,->(name) { where("lower(concat_ws(' ',surname,name)) = ?", name) }
  # scope :find_by_complete_name_inv,->(name) { where("lower(concat_ws(' ',name,surname)) = ?", name) }
  scope :filter, ->(name) { where("name like ? or surname like ? or mdc_user like ? or ('mdc' like ? and mdc_user is not null and mdc_user != '')", "%#{name}%", "%#{name}%", "%#{name}%", "%#{name}%").order(:surname) }
  scope :mdc, -> { where("mdc_user is not null and mdc_user != ''") }
  scope :order_mdc_user, -> { order(:mdc_user)}
  scope :employees, -> { joins(:companies).where("company_id = #{Company.chiarcosso.id} or company_id = #{Company.transest.id}").distinct }
  scope :with_badge, -> { where("id in (select person_id from badge_assignments)") }
  # scope :building_employees, -> { where("people.id in (#{MssqlReference.query({table: 'Autisti', where: {IdMansione: [2,3,5,6,7,11,12,13,14,15,16,17,18,19,20]}}).map{|p| p['IdAutista']}.join(',')})") }
  # scope :drivers, -> { include(:relations).where("relations.name = 'Autista'") }
  # scope :company, ->(name) { joins(:companies).where('company.name like ?',"%#{name}%") }
  def check_properties(comp)
    if comp['name'].upcase != self.name.upcase
      return false
    elsif comp['surname'].upcase != self.surname.upcase
      return false
    end
    return true
  end

  def move_to(person)
    unless person.is_a? Person
      person = Person.find(person)
    end
    self.mssql_references.each do |msr|
      begin
        msr.update(local_object_id: person)
      rescue

      end
    end
  end

  def self.workshop_action(from,to = from)
    Person.where("id in (select distinct person_id from timesheet_records where date(start) between '#{from.strftime("%Y-%m-%d")}' and '#{to.strftime("%Y-%m-%d")}')")
  end

  # Filter drivers out
  def self.building_employees
    refs = MssqlReference.query({table: 'Autisti', where: {IdMansione: [2,3,5,6,7,11,12,13,14,15,16,17,18,19,20]}})
    Person.joins("inner join mssql_references mr on mr.local_object_id = people.id and mr.local_object_type = 'Person'").where("mr.remote_object_id in (#{refs.to_a.map{ |a| a['Idautista']}.join(',')})").distinct
  end

  # People that used the badge in a given month
  def self.present_at_month(time = Time.now)
    Person.where("people.id in "\
                "(select distinct person_id from badge_assignments "\
                  "ba where (('#{time.strftime("%Y-%m")}' between date_format(ba.from,'%Y-%m') and date_format(ba.to,'%Y-%m')) or ('#{time.strftime("%Y-%m-%d")}' > ba.from and ba.to = '1900-01-01')) "\
                "and ba.badge_id in (select distinct badge_id from presence_timestamps pt where month(pt.time) = #{time.strftime('%-m')} and year(pt.time) = #{time.strftime('%Y')}))").distinct

  end

  # Queries mssql db for people with 'attivo' flag set
  def self.active_people(time = Time.now)
    refs = MssqlReference.query({table: 'Autisti', where: {Attivo: 1,Ditta: ['A','T']}})
    pp = Person.present_at_month(time)
    Person.joins("inner join mssql_references mr on mr.local_object_id = people.id and mr.local_object_type = 'Person'").where("mr.remote_object_id in (#{refs.to_a.map{ |a| a['Idautista']}.join(',')}) #{pp.empty? ? '' : "or (people.id in (#{pp.map{|p| p.id}.join(',')}))"}").distinct
  end

  def current_badges
    # Badge.where("id in (select badge_id from badge_assignments where person_id = #{self.id} and badge_assignments.to = '1900-01-01')")
    self.badges
  end

  def last_presence_record
    PresenceRecord.joins("inner join presence_timestamps pt on pt.id = presence_records.start_ts_id").where(person: self).order("pt.time desc").limit(1).first
  end

  def self.present_on_date(date)
    PresenceRecord.where(date: date).map{|pr| pr.person}
  end

  def mechanic?
    self.company_relations.select{ |cr| cr.name == 'Meccanico' || cr.name == 'Meccanico trasfertista' || cr.name == 'Capo Officina'}.count > 0
  end

  def self.mechanics
    # Person.all.select{ |p| p.mechanic? }

    query = <<-QRY
      company_people.company_relation_id in (
        select id from company_relations
        where acting = 1
        and (name = 'Meccanico'
        or name = 'Meccanico trasfertista'
        or name = 'Capo Officina')
      )
    QRY

    Person.joins(:relations).where(query)
  end

  def self.present_mechanics(date)
    wmech = <<-QRY
      company_people.company_relation_id in (
        select id from company_relations
        where acting = 1
        and (name = 'Meccanico'
        or name = 'Meccanico trasfertista'
        or name = 'Capo Officina')
      )
    QRY
    Person.joins(:presence_records)
      .joins(:relations)
      .distinct
      .where("presence_records.date = '#{date.strftime("%y-%m-%d")}'")
      .where(wmech)
    # PresenceRecord.where(date: date).map{|pr| pr.person}.uniq.select{ |p| p.mechanic? }
  end

  def present?(time = Time.now)
    lr = self.last_presence_record(time)
    if lr.nil? || lr.break
      false
    else
      true
    end
  end

  def presence_check(time = Time.now)
    lr = self.last_presence_record
    schedule = WorkingSchedule.find_by(person: self, weekday: time.strftime('%w').to_i-1)
    gl = self.granted_leaves_date(time)
    # byebug if self.list_name == 'De Fazio Eva'
    if lr.nil?
      return :away
    else
      if lr.time_in_record(time)
        #if time is in the last record it's either a break or presence
        if lr.break
          return :away
        elsif schedule.nil?
          return :not_requested
        else
          #if out between working schedule the missing or breaking
          start_time = Time.strptime("#{time.strftime("%Y-%m-%d")} #{schedule.agreement_from.strftime("%H:%M:%S")}","%Y-%m-%d %H:%M:%S")
          end_time = Time.strptime("#{time.strftime("%Y-%m-%d")} #{schedule.agreement_to.strftime("%H:%M:%S")}","%Y-%m-%d %H:%M:%S")
          if time >= start_time && time <= end_time
            return :present
          else
            return :not_requested
          end
        end
      else
        #if not it must be out
        if schedule.nil?
          return :away
        else

          #if out between working schedule then missing or breaking
          start_time = Time.strptime("#{time.strftime("%Y-%m-%d")} #{schedule.agreement_from.strftime("%H:%M:%S")}","%Y-%m-%d %H:%M:%S")
          end_time = Time.strptime("#{time.strftime("%Y-%m-%d")} #{schedule.agreement_to.strftime("%H:%M:%S")}","%Y-%m-%d %H:%M:%S")
          if time >= start_time && time <= end_time
            return :missing if lr.end_ts.nil?
            return :break if time - lr.end_ts.time < schedule.break.to_i*60 && !lr.break
            gl.each do |leave|
              return :away if leave.time_in_leave(time)
            end
            return :missing
          else
            return :away
          end
        end
      end
    end
  end

  def presence_check_style(time = Time.now)
    case self.presence_check(time)
    when :present then
      'background-color: #5f5'
    when :break then
      'background-color: #bf9'
    when :missing then
      'background-color: #f55'
    when :away then
      ''
    when :not_requested then
      'background-color: #ff5'
    end
  end

  def badges(date = nil)
    if date.nil?
      where = "badge_assignments.to = '1900-01-01'"
    else
      where = "(case when badge_assignments.to is null or badge_assignments.to = '1900-01-01' then '#{date.strftime("%Y-%m-%d")}' >= badge_assignments.from else '#{date.strftime("%Y-%m-%d")}' between badge_assignments.from and badge_assignments.to end)"
    end
    Badge.where("id in (select badge_id from badge_assignments where person_id = #{self.id} and #{where})")
  end

  def granted_leaves_date(date = Time.now)
    GrantedLeave.where(person: self).where("'#{date.strftime("%Y-%m-%d")}' between date_format(granted_leaves.from,'%Y-%m-%d') and date_format(granted_leaves.to,'%Y-%m-%d')")
  end

  def has_reference?(table,id)
    !MssqlReference.where(local_object:self,remote_object_table:table,remote_object_id:id).empty?
  end

  def has_relation?(company,relation)
    !CompanyPerson.where(person: self, company: company, company_relation: relation).empty?
  end

  def self.find_by_complete_name name
    Person.where("lower(concat_ws(' ',surname,name)) = ?", name).first
  end

  def self.find_by_complete_name_inv name
    Person.where("lower(concat_ws(' ',name,surname)) = ?", name).first
  end

  def rearrange_mdc_users user
    self.update(:mdc_user => user)
    unless user.nil?
      Person.where(mdc_user: self.mdc_user).where("id != #{self.id}").update(mdc_user: nil)
    end
    mdc = MdcWebservice.new
    mdc.begin_transaction
    Person.mdc.each do |p|
      mdc.insert_or_update_tabgen(Tabgen.new({deviceCode: "|#{ p.mdc_user.upcase}|", key: p.mdc_user, order: 1, tabname: 'USERS', values: [p.mdc_user.upcase,p.mdc_user,p.name,p.surname,p.id]}))
    end
    mdc.commit_transaction
    mdc.end_transaction
    mdc.close_session
  end

  def self.find_by_mdc_user(user)
    # Person.mdc.where(:mdc_user => user).first
    p = MdcUser.find_by(user: user).assigned_to_person_id
    Person.find(p) unless p.nil?
  end

  def self.find_or_create(person)

    #person -> id: dashboard person id
    #          mssql_id: sql srver id
    #          table: sql server table
    #          data: { name, surname }

    if !person[:id].nil?
      p = Person.find(person[:id].to_i)
      person[:table] = 'Autisti' if person[:table].nil?
      if p.nil? and !person[:data].nil?
        p = Person.create(person[:data])
      end
      unless person[:mssql_id].nil?
        ref = MssqlReference.query({table: person[:table], where: {id: person[:mssql_id], nome: :not_null}}).first
        MssqlReference.create(local_object: p, remote_object_table: person[:table], remote_object_id: person[:mssql_id].to_i)
      end
      return p
    end

    if !person[:mssql_id].nil?
      p = Person.find_by_reference(person[:mssql_id].to_i, person[:table])

      if p.nil?
        case person[:table]
        when 'Autisti' then
          where = {IdAutista: person[:mssql_id].to_i}
        when 'Clienti' then
          where = {IdCliente: person[:mssql_id].to_i}
        end
        ref = MssqlReference.query({table: person[:table], where: where}).first

        case person[:table]
        when 'Autisti' then
          if ref['nome'].nil?
            tmp = ref['Nominativo'].split(' ',2)
            ref['nome'] = tmp[0]
            ref['cognome'] = tmp[1]
          end
          p = Person.create(name: ref['nome'], surname: ref['cognome'])
        when 'Clienti' then
          tmp = ref['RagioneSociale'].split(' ',2)
          p = Person.create(name: tmp[0], surname: tmp[1])
        end

        MssqlReference.create(local_object: p, remote_object_table: person[:table], remote_object_id: person[:mssql_id].to_i)
      end
      return p
    end
  end

  def self.find_by_reference(id,table = 'Autisti')
    ms = MssqlReference.find_by(remote_object_id: id.to_i, remote_object_table: table)
    Person.find(ms.local_object_id) unless ms.nil?
  end

  def complete_name
    self.name+' '+self.surname
  end

  def list_name
    self.surname+' '+self.name
  end

  def complete_list_name
    "#{self.surname} #{self.name} (#{companies.last.name})"
  end
end
