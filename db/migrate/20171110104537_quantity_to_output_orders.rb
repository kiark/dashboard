class QuantityToOutputOrders < ActiveRecord::Migration[5.0]
  def change
    change_column(:articles,:containedAmount,:decimal,precision:12,scale:3,null: false, default: 1.0)
    add_column(:output_order_items,:quantity,:decimal,precision:12,scale:3,null: false, default: 1.0)
    add_column(:items,:remaining_quantity,:decimal,precision:12,scale:3,null: false, default: 0.0)

    Item.available_items.each do |i|
      i.update(remaining_quantity: i.article.containedAmount)
    end
  end
end
