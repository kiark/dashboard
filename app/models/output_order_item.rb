class OutputOrderItem < ApplicationRecord
  resourcify

  before_destroy :recover_item
  belongs_to :item
  has_one :article, through: :item
  belongs_to :output_order

  @new_item = false

  def new_item(set = false)
    if set
      @new_item = true
    end
    @new_item
  end
  
  def actual_price
    (self.item.actual_box_price / self.item.article.containedAmount) * self.quantity
  end

  def price
    (self.item.price / self.item.article.containedAmount) * self.quantity
  end

  def discount
    self.item.discount
  end

  def complete_price
    price = self.actual_price.round(2).to_s+' €'
    if (self.item.discount.to_f > 0)
       price += " \n("+self.price.round(2).to_s+' -'+self.discount.to_s+'%'+')'
    end
    price.tr('.',',')#+"\n Scatola: #{self.item.complete_price}"
  end

  def recover_item
    i = self.item
    i.update(remaining_quantity: i.remaining_quantity + self.quantity)
    i.item_relations.clear
  end

end
