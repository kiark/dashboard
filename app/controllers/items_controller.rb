class ItemsController < ApplicationController
  before_action :set_item, only: [:show, :edit, :update, :destroy]
  before_action :set_article_for_order, only: [:add_item_to_storage]
  before_action :set_items_for_order, only: [:add_item_to_storage]
  before_action :set_vehicle_for_order, only: [:add_item_to_storage]
  # GET /items
  # GET /items.json
  def index
    @search = search_params.nil?? '' : search_params
    @selected_items = Item.filter(search_params).distinct
    render :partial => 'items/index'
  end

  # GET /items/1
  # GET /items/1.json
  def show
  end

  def storage_insert
    @items = Array.new
    tmp = Hash.new
    Item.unpositioned.each do |un|
      d = un.expiringDate.nil?? 'noDate' : un.expiringDate.strftime('%Y%m%d')
      if tmp[un.article.id.to_s+'-'+un.serial+'-'+d].nil?
        un.setAmount 1
        tmp[un.article.id.to_s+'-'+un.serial+'-'+d] = un
      else
        tmp[un.article.id.to_s+'-'+un.serial+'-'+d].setAmount tmp[un.article.id.to_s+'-'+un.serial+'-'+d].amount+1
      end
    end
    tmp.each do |k,u|
      @items << u
    end
    render :partial => 'items/new_order'
  end

  def vehicle_insert
    @items = Array.new
    @vehicle = Vehicle.new
    render :partial => 'items/vehicle_order'
  end

  def store
    msg = 'Ok'
    itemsToStore = store_params[:items_to_store].split
    position = PositionCode.findByCode(store_params[:position_code])
    itemsToStore.each do |i|
      itm = Item.find(i.to_i)
      if itm.nil? || position.nil?
        msg = 'Errore'
      end
      itm.position_code = position
      itm.save
      msg = msg+' '+itm.actualBarcode
    end
    render :json => msg
  end

  def add_item_to_storage

    @items = Array.new
    # tmp = Hash.new
    # Item.unpositioned.each do |un|
    #   d = un.expiringDate.nil?? 'noDate' : un.expiringDate.strftime('%Y%m%d')
    #   if tmp[un.article.id.to_s+'-'+un.serial+'-'+d].nil?
    #     un.setAmount 1
    #     tmp[un.article.id.to_s+'-'+un.serial+'-'+d] = un
    #   else
    #     tmp[un.article.id.to_s+'-'+un.serial+'-'+d].setAmount tmp[un.article.id.to_s+'-'+un.serial+'-'+d].amount+1
    #   end
    # end
    # tmp.each do |k,u|
    #   @items << u
    # end

    @newItems.each do |i,k|
      item = Item.new
      item.setAmount k[:amount].to_i
      item.price = k[:price].to_f
      item.discount = k[:discount].to_f
      item.serial = k[:serial]
      item.state = k[:state].to_i
      item.expiringDate = k[:expiringDate]
      item.article = Article.find(k[:article].to_i)
      item.position_code = PositionCode.findByCode('P0 X0 0-x')
      item.barcode = nil #item.generateBarcode #SecureRandom.base58(10)
      @items << item
    end

    # if params[:barcode] != ''
    if @vehicle.id.nil?
      partial = 'items/new_order'
    else
      partial = 'items/vehicle_order'
    end
    unless @article.nil? || @save
      item = Item.new
      item.article = @article
      item.setAmount 1
      item.barcode = nil #item.generateBarcode #SecureRandom.base58(10)
      @items << item
    end

    if @save
      unpositionedItems = Item.unpositioned.to_a
      @items.each do |i|
        # i.transportDocument = @transportDocument
        # OrderArticle.create({order: @order, article: i.article, amount: i.amount})
        i.setActualItems
        i.amount.times do
          item = Item.new(i.attributes)
          item.barcode = nil #item.generateBarcode #SecureRandom.base58(10)

          unpositionedItems.each do |unpItem|
            if unpItem.article == item.article && unpItem.price == item.price && unpItem.discount == item.discount && unpItem.serial == item.serial && unpItem.state == item.state && unpItem.expiringDate == item.expiringDate
              item = unpItem
              break
            end
          end
          if item.id.nil?
            item = Item.create(i.attributes)
          else
            unpositionedItems -= [item]
          end
          i.addActualItems item.id
          unless @vehicle.id.nil?

          end
          item.save
          item.item_relations << ItemRelation.create(:since => Time.now)
          if item.barcode.nil? && (item.article.barcode.size == 0 || item.serial.size > 0 || !item.expiringDate.nil?)
            item.barcode = item.generateBarcode
            item.save
            item.printLabel
          end
          i.barcode = item.barcode
        end
      end
      @registeredItems = @items
      @items = Array.new
      @newItems = Array.new
      @save = false

      respond_to do |format|
        format.js { render :js, :partial => partial }
      end
    else
      respond_to do |format|
        format.js { render :js, :partial => partial }
      end
    end

  end

  def from_order
    render :partial => 'items/from_order'
  end

  # GET /items/new
  def new
    @item = Item.new
  end

  # GET /items/1/edit
  def edit
  end


  # POST /items
  # POST /items.json
  def create
    @item = Item.new(item_params)

    respond_to do |format|
      if @item.save
        format.html { redirect_to @item, notice: 'Item was successfully created.' }
        format.json { render :show, status: :created, location: @item }
      else
        format.html { render :new }
        format.json { render json: @item.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /items/1
  # PATCH/PUT /items/1.json
  def update
    respond_to do |format|
      if @item.update(item_params)
        format.html { redirect_to @item, notice: 'Item was successfully updated.' }
        format.json { render :show, status: :ok, location: @item }
      else
        format.html { render :edit }
        format.json { render json: @item.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /items/1
  # DELETE /items/1.json
  def destroy
    @item.item_relations.each do |ir|
      if ir.office.nil? && ir.vehicle.nil? && ir.person.nil?
        ir.delete
      end
    end
    respond_to do |format|
      if @item.destroy
        @selected_items = Item.filter(search_params).distinct
        format.js { render :partial => 'items/index', notice: 'Pezzo eliminato.' }
      else
        @selected_items = Item.filter(search_params).distinct
        format.js { render :partial => 'items/index', notice: 'Impossibile eliminare il pezzo.' }
      end
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_item
      @item = Item.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def item_params
      params.require(:item).permit(:article_id, :purchaseDate, :price, :price, :discount, :discount, :serial, :state, :notes, :expiringDate, :transportDocument_id)
    end

    def store_params
      params.require(:store).permit(:items_to_store,:position_code)
    end

    def set_article_for_order
      if params['commit'] == '>' && params[:article].to_i > 0
        @article = Article.find(params[:article].to_i)
        @articles = Array.new
        @articles << @article
        @newArticle = false
      elsif Article.where(barcode: params[:barcode]).count > 0
        @articles = Article.where(barcode: params[:barcode])
        @article = @articles.first
        @newArticle = false
      elsif !@save
        @newArticle = true
        @article = Article.new({:barcode => params[:barcode]})
        @articles = Array.new
        @article.setBarcodeImage
        @articles << @article
      end
    end

    def set_items_for_order
      # if params[:items].nil?
      if items_params.nil?
        @newItems = Array.new
      else
        @newItems = items_params
      end
    end

    def set_vehicle_for_order
      unless params[:vehicle] == '' || params[:vehicle].nil?
        @vehicle = Vehicle.find(params.require(:vehicle).to_i)
      else
        @vehicle = Vehicle.new
      end
    end

    def items_params
      unless params[:commit].nil?
        @save = params['commit'][0..7] == 'Conferma' ? true : false
      end
      unless params[:items].nil?
        params.require(:items).tap do |itm|
          itm.permit(:article, :price, :discount, :serial, :state, :expiringDate, :amount)
        end
      end
    end

    def search_params
      unless params[:search].nil?
        params.require(:search)
      end
    end

end
