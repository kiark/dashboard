class PresenceRecord < ApplicationRecord
  belongs_to :start_ts, class_name: 'PresenceTimestamp', foreign_key: :start_ts_id
  belongs_to :end_ts, class_name: 'PresenceTimestamp', foreign_key: :end_ts_id
  belongs_to :person

  enum weekdays: ['Dom.','Lun.','Mar.','Mer.','Gio.','Ven.','Sab.']

  def duration_label(calculated = true)
    if calculated
      "#{self.calculated_duration/3600}:#{((self.calculated_duration%3600)/60).to_s.rjust(2,'0')}:#{(((self.calculated_duration%3600)%60)).to_s.rjust(2,'0')}"
    else
      "#{self.actual_duration/3600}:#{((self.actual_duration%3600)/60).to_s.rjust(2,'0')}:#{(((self.actual_duration%3600)%60)).to_s.rjust(2,'0')}"
      # ts_start = self.start_ts.time
      # ts_end = self.end_ts.nil? ? self.start_ts.time : self.end_ts.time
      # duration = (ts_end - ts_start).to_i
      # "#{duration/3600}:#{((duration%3600)/60).to_s.rjust(2,'0')}:#{(((duration%3600)%60)).to_s.rjust(2,'0')}"
    end
  end

  def self.round_timestamp(timestamp)
    #find the time from the beginning of the day
    d = DateTime.strptime(timestamp.strftime("%Y-%m-%d 00:00:00"),"%Y-%m-%d %H:%M:%S")

    #round it to the last half an hour
    d2 = (timestamp.to_i - d.to_i)%(60*30)

    #rebuild the timestamp
    # DateTime.strptime("#{timestamp.strftime("%Y-%m-%d")} #{"#{d2/3600}:#{((d2%3600)/60).to_s.rjust(2,'0')}:#{(((d2%3600)%60)).to_s.rjust(2,'0')}"}", "%Y-%m-%d %H:%M:%S")
    DateTime.strptime("#{timestamp.strftime("%Y-%m-%d")} #{(timestamp-d2).strftime("%H:%M:%S")} #{PresenceController.actual_timezone(timestamp)}", "%Y-%m-%d %H:%M:%S %Z")
  end

  def self.recalculate(date,person)

    #remove previously recorded data
    PresenceRecord.where(date: date, person: person).each do |pr|
      pr.delete
    end

    #get badges
    badges = person.badges(date)

    #get day schedule
    working_schedule = WorkingSchedule.get_schedule(date,person)

    #for every timestamp on that day with those badges calculate records
    presence_timestamps = PresenceTimestamp.where("deleted = 0 and sensor_id in (select id from sensors where presence_relevant = 1) and badge_id in (#{badges.map{|b|b.id}.join (',')})").where("(year(time) = #{date.strftime('%Y')} and month(time) = #{date.strftime('%m')} and day(time) = #{date.strftime('%d')})").order(time: :asc).to_a
    presence_timestamps.each_with_index do |pts,index|
      if index%2 == 0

        next_pts = presence_timestamps[index+1]

        #if timestamp is even (starting from 0) it's an entering ts
        pts.update(entering: true)

        #calculate entering and exit
        if index == 0 && !working_schedule.nil?
          #if it's the first timestamp of the day compare starting time with agreed schedule
          calculated_start = DateTime.strptime("#{date.strftime("%Y-%m-%d")} #{working_schedule.agreement_from.strftime("%H:%M:%S")}","%Y-%m-%d %H:%M:%S")
          #check delay
          # if pts.time.strftime("%H:%M") > working_schedule.agreement_from.strftime("%H:%M")
          #   delay = Time.strptime("#{pts.time.strftime("%H:%M")}","%H:%M") - Time.strptime("#{working_schedule.agreement_from.strftime("%H:%M")}","%H:%M")
          #   delayed = 15/delay.to_i+1
          #   byebug
          # end
        else
          #otherwise get it from the timestamp
          calculated_start = pts.time.to_datetime
        end
        if next_pts.nil?
          #if it's the last timestamp, ending time is open
          calculated_end = nil
        else
          #otherwise
          if presence_timestamps[index+2].nil? && !working_schedule.nil?
            #if the next is the last get ending time from working schedule
            # calculated_end = DateTime.strptime("#{date.strftime("%Y-%m-%d")} #{working_schedule.agreement_to.strftime("%H:%M:%S")}","%Y-%m-%d %H:%M:%S")
            calculated_end = PresenceRecord.round_timestamp(next_pts.time)
          else
            #if not get it from the next timestamp
            calculated_end = next_pts.nil? ? nil : next_pts.time.to_datetime
          end
        end

        PresenceRecord.create(date: date,
                            person: person,
                            start_ts: pts,
                            end_ts: next_pts,
                            calculated_start: calculated_start,
                            calculated_end: calculated_end,
                            actual_duration: next_pts.nil? ? 0 : (next_pts.time - pts.time).round,
                            calculated_duration: next_pts.nil? ? 0 : (calculated_end.to_i - calculated_start.to_i),
                            break: false)
      else

        next_pts = presence_timestamps[index+1]

        #if timestamp is odd (starting from 0) it's an exiting ts
        pts.update(entering: false)

        #calculate entering and exit (if it's the last one it was already registered as the ending of the previous)
        unless next_pts.nil?

          #start must be the pts' time
          calculated_start = pts.time.to_datetime

          # #end will be the next timetamp
          # calculated_end = next_pts.time.to_datetime
          calculated_end = pts.time+working_schedule.break.minutes

          PresenceRecord.create(date: date,
                              person: person,
                              start_ts: pts,
                              end_ts: next_pts,
                              calculated_start: calculated_start,
                              calculated_end: calculated_end,
                              actual_duration: next_pts.nil? ? 0 : (next_pts.time - pts.time).round,
                              calculated_duration: (calculated_end.to_i - calculated_start.to_i).round,
                              break: true)
        end
      end
    end
  end
end