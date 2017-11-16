class QuantityToOutputOrders < ActiveRecord::Migration[5.0]
  def change
    add_column(:output_order_items,:quantity,:decimal,precision:7,scale:2,null: false, default: 1)
    add_column(:items,:remaining_quantity,:decimal,precision:7,scale:2,null: false, default: 0)
    Item.unassigned.each do |i|
      i.update(remaining_quantity: i.article.containedAmount)
    end
  end
end
