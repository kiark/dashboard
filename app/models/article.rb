class Article < ApplicationRecord
  resourcify
  include BarcodeUtility
  require 'barby/outputter/cairo_outputter'
  # require 'barby/outputter/png_outputter'
  require 'barby/barcode/ean_13'
  require 'barby/barcode/ean_8'

  has_and_belongs_to_many :categories, class_name: "ArticleCategory",
                                     join_table: "article_categorizations",
                                     foreign_key: :category_id,
                                     association_foreign_key: :article_id

  has_many :items
  belongs_to :manufacturer, class_name: "Company"

  scope :filter, ->(search) { joins(:manufacturer).where("articles.barcode LIKE '%#{search}%' OR articles.description LIKE '%#{search}%' OR companies.name LIKE '%#{search}%' OR articles.name LIKE '%#{search}%' OR articles.manufacturerCode LIKE '%#{search}%'")}
  scope :no_barcode, -> { where(barcode: '') }
  scope :manufacturer, ->(search) { include(:company).where("manufacturer_id = companies.id").where("companies.name LIKE '%#{search}%'")}
  # scope :reserve_check, -> { group(:id).left_outer_joins(:items).having('count(items.id) < minimalReserve or (minimalReserve = 0 and count(items.id) > 0)') }
  scope :reserve_check, -> { where("id in (select article_id from items inner join articles a on items.article_id = a.id left join output_order_items o on o.item_id = items.id where o.output_order_id is null group by article_id having (count(items.id) < articles.minimalReserve or (articles.minimalReserve = 0 and count(items.id) > 0))) or id not in (select article_id from items group by article_id)") }
  # scope :position_codes, ->(article) { include(:items).include(:position_code).distinct }

  enum measure_unit: [:pezzi,:kg,:l]

  def self.incompleteItems
    Article.all
  end

  def position_codes_text
    pc = Set.new
    self.items.each do |i|
      pc << i.position_code.code
    end
    pc
  end

  def self.inventory(search)
    search_text = (search.nil? or search == "") ? 'Inventario completo' : "Ricerca: `#{search}`"
    pdf = Prawn::Document.new
    pdf.text "Inventario magazzino al #{Time.now.strftime("%d/%m/%Y %H:%M:%S")}"
    pdf.text search_text

    table = [['Articolo','Quantità','Posizioni']]
    Article.filter(search).order(:name).each do |a|
      table << ["#{a.complete_name}","#{a.availability.size} / #{a.minimalReserve}","#{a.position_codes_text.to_a.join("\n")}"]
    end

    pdf.move_down 20
    pdf.table table,
      # :border_style => :grid,
      # :font_size => 11,
      :position => :center,
      :column_widths => { 0 => 265, 1 => 190, 2 => 85},
      # :align => { 0 => :right, 1 => :left, 2 => :right, 3 => :left},
      :row_colors => ["d2e3ed", "FFFFFF"]

    pdf.bounding_box([pdf.bounds.right - 50,pdf.bounds.bottom], :width => 60, :height => 20) do
    	count = pdf.page_count
    	pdf.text "Page #{count}"
    end
    pdf
  end

  def self.reserve
    pdf = Prawn::Document.new
    pdf.text "Scorte minime e disponibilità magazzino al #{Time.now.strftime("%d/%m/%Y %H:%M:%S")}"

    table = [['Articolo','Quantità','Posizioni']]
    Article.reserve_check.order(:name).each do |a|
      table << ["#{a.complete_name}","#{a.availability.size} / #{a.minimalReserve}","#{a.position_codes_text.to_a.join("\n")}"]
    end

    pdf.move_down 20
    pdf.table table,
      # :border_style => :grid,
      # :font_size => 11,
      :position => :center,
      :column_widths => { 0 => 265, 1 => 190, 2 => 85},
      # :align => { 0 => :right, 1 => :left, 2 => :right, 3 => :left},
      :row_colors => ["d2e3ed", "FFFFFF"]

    pdf.bounding_box([pdf.bounds.right - 50,pdf.bounds.bottom], :width => 60, :height => 20) do
    	count = pdf.page_count
    	pdf.text "Page #{count}"
    end
    pdf
  end
  # def availability
  #   Item.available_items.article(self)
  # end

  def under_reserve?(*checked)
    self.minimalReserve.to_f > self.availability(checked).size
  end

  def lastPrice
    i = Item.newestItem(self).first
    unless i.nil?
      i.complete_price
    end
  end

  def availability(*checked)
    unless checked.empty?
      Item.article(self).available_items - checked[0]
    else
      Item.article(self).available_items
    end
  end

  def setBarcodeImage
    unless self.barcode == ''
      if barcode = checkBarcode(self.barcode)
        @blob = Barby::CairoOutputter.new(barcode).to_png #Raw PNG data
        File.write("public/images/#{self.barcode}.png", @blob)
      else
        self.barcode = 'Codice non valido'
      end
    end
  end

  def getManufacturer
    self.manufacturer.nil?? nil : self.manufacturer.id.to_s
  end

  def categoriesList
    list = Array.new
    self.categories.each do |cat|
      list << cat.name
    end
    list.join(', ')
  end

  def manufacturer_name
    if self.manufacturer.nil?
      "Generico"
    else
      self.manufacturer.name
    end
  end

  def complete_name
    unless self.manufacturer.nil?
      self.manufacturer.name + " " + self.manufacturerCode
    else
      "Generico" + " " + self.name.to_s
    end
  end

  def printLabel
    label = Zebra::Epl::Label.new(
      :width         => 385,
      :length        => 180,
      :print_speed   => 3,
      :print_density => 9
    )
    # box = Zebra::Epl::Box.new :position => [0, 0], :end_position => [385, 180], :line_thickness => 2
    # label << box

    text  = Zebra::Epl::Text.new :data => self.expiringDate?? 'Sc. '+self.expiringDate.strftime('%d/%m/%Y') : '', :position => [10, 0], :font => Zebra::Epl::Font::SIZE_3
    label << text
    # text  = Zebra::Epl::Text.new :data => self.position_code.code, :position => [220, 10], :font => Zebra::Epl::Font::SIZE_2
    # label << text
    text  = Zebra::Epl::Text.new :data => self.article.complete_name, :position => [10, 30], :font => Zebra::Epl::Font::SIZE_2
    label << text
    text  = Zebra::Epl::Text.new :data => self.serial.nil?? '' : 'Mat. '+self.serial, :position => [10, 60], :font => Zebra::Epl::Font::SIZE_4
    label << text
    barcode = Zebra::Epl::Barcode.new(
      :data                      => self.barcode,
      :position                  => [10, 110],
      :height                    => 40,
      :print_human_readable_code => true,
      :narrow_bar_width          => 2,
      :wide_bar_width            => 4,
      :type                      => Zebra::Epl::BarcodeType::CODE_128_AUTO
    )
    label << barcode
    print_job = Zebra::PrintJob.new "zebra"
    print_job.print label
  end
  # def checkBarcode
  #   begin
  #     if self.barcode[0..-2].size == 12
  #       Barby::EAN13.new(self.barcode[0..-2])
  #     elsif self.barcode[0..-2].size == 7
  #       Barby::EAN8.new(self.barcode[0..-2])
  #     else
  #       return false
  #     end
  #   rescue
  #     return false
  #   end
  # end

end
