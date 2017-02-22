class OrdersController < ApplicationController
  before_action :set_order, only: [:show, :edit, :update, :destroy]
  before_action :set_article_for_order, only: [:add_item_to_new_order]
  before_action :set_items_for_order, only: [:add_item_to_new_order]
  before_action :output_params, only: [:add_item, :output]
  before_action :exit_params, only: [:exit_order,:confirm_order,:destroy_output_order, :print_pdf, :print_pdf_module]
  # GET /orders
  # GET /orders.json
  def index
    @orders = Order.all
  end

  # GET /orders/1
  # GET /orders/1.json
  def show
  end

  # GET /orders/new
  def new
    @order = Order.new
  end

  # GET /orders/1/edit
  def edit
  end

  def print_pdf
    respond_to do |format|
      format.pdf do
        pdf = @order.print
        send_data pdf.render, filename:
        "lista_ordine_uscita_nr_#{@order.id}.pdf",
        type: "application/pdf"
      end
    end
  end

  def print_pdf_module
    respond_to do |format|
      format.pdf do
        pdf = @order.print_module
        send_data pdf.render, filename:
        "modulo_dotazione_#{@order.id}.pdf",
        type: "application/pdf"
      end
    end
  end

  def output
    # @destination = output_params
    case @destination.to_sym
    when :Person
      @recipient = Person.all.first
    when :Worksheet
      @recipient = Vehicle.all.first
    when :Vehicle
      @recipient = Vehicle.all.first
    when :Office
      @recipient = Office.all.first
    end
    @search = search_params.nil?? '' : search_params
    @checked_items = Array.new
    @selected_items = Item.available_items.unassigned.firstGroupByArticle(search_params,@checked_items)
    # render :partial => 'items/index'
    respond_to do |format|
      format.js { render :js, :partial => 'orders/output' }
    end
  end

  def add_item
    # @destination = output_params
    @search = search_params.nil?? '' : search_params
    @checked_items = chk_list_params
    unless @newItem.nil?
      @checked_items << @newItem
    end
    @selected_items = Item.firstGroupByArticle(search_params,@checked_items)
    # render :partial => 'items/index'
    # @selected_items -= @checked_items
    if @save
      order = OutputOrder.create(createdBy: current_user,destination_id: @recipient.id,destination_type: @destination)
      @checked_items.each do |ci|
        order.items << ci
      end
      # redirect_to storage_output_path
    end
    respond_to do |format|
      if @save
        @partial = 'storage/output_initial'
        format.js { render :js, :partial => 'storage/output_initial_js' }
        # format.js { render :js 'storage/index' }
      else
        format.js { render :js, :partial => 'orders/output' }
      end
    end
  end

    def output_office
      @selected_items = Array.new
      @items = Item.filter(search_params)
      respond_to do |format|
        format.js { render :js, :partial => 'items/output' }
      end
    end
  # POST /orders
  # POST /orders.json
  def create
    @order = Order.new(order_params)

    respond_to do |format|
      if @order.save
        format.html { redirect_to @order, notice: 'Order was successfully created.' }
        format.json { render :show, status: :created, location: @order }
      else
        format.html { render :new }
        format.json { render json: @order.errors, status: :unprocessable_entity }
      end
    end
  end

  def exit_order
    render :partial => 'output_orders/exit'
  end

  def confirm_order
    @order.processed = true;
    if @order.save
      @msg = 'Ordine evaso'
    else
      @msg = 'Errore'
    end
      render :partial => 'layouts/messages'
  end

  def new_order
    @order = Order.new
    @order.supplier = Company.find(2)
    @items = Array.new
    @transportDocument = TransportDocument.new
    @transportDocument.date = DateTime.now.to_date
    render :partial => 'items/new_order'
  end

  def scan_order
    render :partial => 'transport_documents/scan_document'
  end

  def add_item_to_new_order
    @order = Order.new
    @transportDocument = TransportDocument.new
    @items = Array.new
    @order.supplier = Company.get(params[:order]['supplier'])
    @order.date = params[:order][:purchaseDate]
    @transportDocument.number = params[:order][:transportDocument]
    @transportDocument.sender = Company.get(params[:order][:supplier])
    @transportDocument.vector = Company.get(params[:order][:vector])
    @transportDocument.date = params[:order][:purchaseDate]
    @newItems.each do |i,k|
      item = Item.new
      item.setAmount k[:amount].to_i
      item.price = k[:price].to_f
      item.discount = k[:discount].to_f
      item.serial = k[:serial]
      item.state = k[:state].to_i
      item.expiringDate = k[:expiringDate]
      item.article = Article.find(k[:article].to_i)
      item.barcode = SecureRandom.base58(10)
      @items << item
    end

    if params[:barcode] != ''
      item = Item.new
      item.article = @article
      item.setAmount 1
      item.barcode = SecureRandom.base58(10)
      @items << item
    end

    if @save
      @items.each do |i|
        # i.transportDocument = @transportDocument
        OrderArticle.create!({order: @order, article: i.article, amount: i.amount})
        i.amount.times do
          item = Item.create!(i.attributes)
          @transportDocument.items << item
        end
      end
      @transportDocument.save
      @order.transport_documents << @transportDocument
      @order.save
    end

    respond_to do |format|
      format.js { render :js, :partial => 'items/new_order' }
    end
  end

  # PATCH/PUT /orders/1
  # PATCH/PUT /orders/1.json
  def update
    respond_to do |format|
      if @order.update(order_params)
        format.html { redirect_to @order, notice: 'Order was successfully updated.' }
        format.json { render :show, status: :ok, location: @order }
      else
        format.html { render :edit }
        format.json { render json: @order.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /orders/1
  # DELETE /orders/1.json
  def destroy_output_order

    if @order.delete
      @msg = 'Ordine eliminato'
    else
      @msg = 'Errore'
    end
      render :partial => 'layouts/messages'
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_order
      @order = Order.find(params[:id])
    end

    def exit_params
      @order = OutputOrder.find(params.require(:id))
    end

    def set_article_for_order
      if Article.where(barcode: params[:barcode]).count > 0
        @articles = Article.where(barcode: params[:barcode])
        @article = @articles.first
        @newArticle = false
      else
        @newArticle = true
        @article = Article.new({:barcode => params[:barcode]})
        @articles = Array.new
        @article.setBarcodeImage
        @articles << @article
      end
    end

    def set_items_for_order
      if params[:items].nil?
        @newItems = Array.new
      else
        @newItems = items_params
      end
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def order_params
      params.require(:order).permit(:date, :supplier, :vector, :transportDocument, :purchaseDate)
    end

    def items_params
      @save = params['commit'].nil?? false : true
      params.require(:items).tap do |itm|
        itm.permit(:article, :price, :discount, :serial, :state, :expiringDate, :amount)
      end
    end

    def output_params
      @destination = params.require(:destination)

      case params.require(:destination).to_sym
      when :Person
        @recipient = params[:recipient].nil?? Person.all.first : Person.find(params.require(:recipient).to_i)
      when :Office
        @recipient = params[:recipient].nil?? Office.all.first : Office.find(params.require(:recipient).to_i)
      when :Vehicle
        @recipient = params[:recipient].nil?? Vehicle.all.first : Vehicle.find(params.require(:recipient).to_i)
      when :Worksheet
        unless params[:recipient].nil?
          @recipient = Worksheet.findByCode(params.require(:recipient))
          if @recipient.nil?
            @recipient = Worksheet.create(:code => params.require(:recipient), :vehicle_id => params.require(:vehicle))
          end
        else
          @recipient = Worksheet.all.first
        end
      end
      unless params[:item].nil?
        @newItem = Item.find(params.require(:item).to_i)
      end
    end

    def chk_list_params
      @save = params['commit'].nil?? false : true
      case params.require(:destination).to_sym
      when :Person
        @recipient = params[:recipient].nil?? Person.all.first : Person.find(params.require(:recipient).to_i)
      when :Office
        @recipient = params[:recipient].nil?? Office.all.first : Office.find(params.require(:recipient).to_i)
      when :Vehicle
        @recipient = params[:recipient].nil?? Vehicle.all.first : Vehicle.find(params.require(:recipient).to_i)
      when :Worksheet
        unless params[:recipient].nil?
          @recipient = Worksheet.findByCode(params.require(:recipient))
          if @recipient.nil?
            @recipient = Worksheet.create(params.require(:recipient), :vehicle_id => params.require(:vehicle))
          end
        else
          @recipient = Worksheet.all.first
        end
      end
      unless params[:items].nil?
        itms = Array.new
        params.require(:items).tap do |itm|
          itm.each do |i|
            id = i.require(:id)
            unless id.nil?
              itms << Item.find(id)
            end
          end
        end
        itms.reverse
      else
        Array.new
      end
    end

    def search_params
      unless params[:search].nil?
        if params[:search].length == 0
          return params[:search]
        end
        params.require(:search)
      end
    end
end
