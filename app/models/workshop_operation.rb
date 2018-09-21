class WorkshopOperation < ApplicationRecord

  belongs_to :worksheet
  belongs_to :user
  has_one :vehicle, through: :worksheet

  scope :to_notification, ->(protocol) { where(myofficina_reference: protocol.to_i) }

  def real_duration_label
    "#{(self.real_duration.to_i/3600).floor.to_s.rjust(2,'0')}:#{((self.real_duration.to_i/60)%60).floor.to_s.rjust(2,'0')}:#{(self.real_duration.to_i%60).floor.to_s.rjust(2,'0')}"
  end

  def operator
    self.user.person unless self.user.nil?
  end

  def self.reset_worksheet
    WorkshopOperation.all.each do |wo|
      wo.reset_worksheet
    end
  end

  def reset_worksheet
    odl = EurowinController.get_odl_from_notification(self.myofficina_reference)
    if odl.nil? || (odl['CodiceAnagrafico'] != 'OFF00001' && odl['CodiceAnagrafico'] == 'OFF00047')
      self.delete
    else
      self.update(worksheet: Worksheet.find_or_create_by_code("EWC*#{odl['Protocollo']}"))
    end
  end

  def self.to_notification_or_create(sgn)

    WorkshopOperation.create(name: 'Lavorazione', myofficina_reference: sgn['Protocollo'], worksheet: Worksheet.find_by(code: "EWC*#{sgn['SchedaInterventoProtocollo']}")) if WorkshopOperation.to_notification(sgn['Protocollo']).count < 1
    WorkshopOperation.to_notification(sgn['Protocollo'])
  end

  def ew_notification
    EurowinController::get_notification(self.myofficina_reference)
  end

  def self.get_from_sgn sgn
    WorkshopOperation.where(myofficina_reference: sgn)
  end

  def siblings
    WorkshopOperation.where(myofficina_reference: self.myofficina_reference) - [self]
  end

  def self.exist_or_create(worksheet,sgn)
    WorkshopOperation.create(name: 'Lavorazione', myofficina_reference: sgn, worksheet: worksheet) unless WorkshopOperation.where(myofficina_reference: sgn).count > 0
  end
end
