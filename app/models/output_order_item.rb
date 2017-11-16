class OutputOrderItem < ApplicationRecord
  resourcify

  belongs_to :item
  belongs_to :output_order

  def actualPrice
    (self.item.actualPrice / self.item.article.containedAmount) * self.quantity
  end

  def price
    (self.item.price / self.item.article.containedAmount) * self.quantity
  end

  def discount
    self.item.discount
  end

  def complete_price
    price = self.actualPrice.round(2).to_s+' €'
    if (self.item.discount.to_f > 0)
       price += " \n("+self.price.to_s+' -'+self.discount.to_s+'%'+')'
    end
    price.tr('.',',')+"\n Scatola: #{self.item.complete_price}"
  end

end
