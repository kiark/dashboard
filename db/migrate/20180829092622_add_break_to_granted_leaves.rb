class AddBreakToGrantedLeaves < ActiveRecord::Migration[5.0]
  def change
    add_column :granted_leaves, :break, :integer, null: false, default: 0
  end
end
