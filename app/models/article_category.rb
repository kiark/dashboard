class ArticleCategory < ApplicationRecord
  resourcify
  # has_ancestry cache_depth: true, orphan_strategy: :restrict

  # scope :parents, -> { where ('ancestry IS NULL') }

  has_and_belongs_to_many :parentCategories, class_name: "ArticleCategory",
                                     join_table: "article_categories_relations",
                                     foreign_key: :child_id,
                                     association_foreign_key: :parent_id

  has_and_belongs_to_many :childCategories, class_name: "ArticleCategory",
                                      join_table: "article_categories_relations",
                                      foreign_key: :parent_id,
                                      association_foreign_key: :child_id

  # has_many :relations, :foreign_key => "parent_id",
  #     :class_name => "Friendship"
  # has_many :parents, through: => :relation
  # has_many :children, through: => :relation

  def relativeDepthSet(depth)
    @relativeDepth = depth
  end

  def relativeDepth
    @relativeDepth
  end

  def self.root
    ArticleCategory.all.select { |ac| ac.parentCategories.empty? }
  end

  def self.tree
    ArticleCategory.all.sort { |ac| ac.depth }
  end

  def childrenList
    self.childCategories.ids.map(&:to_s).join('-')
  end

  def hasDirectRelation?(relative)
    if self.childCategories.to_a.index(relative).nil? && self.parentCategories.to_a.index(relative).nil?
      false
    else
      true
    end
  end

  def childrenTree(list)
    if self.parentCategories.empty?
      self.relativeDepthSet(0)
    end
    childrenArray = Array.new
    list.each do |l|
      if l.to_i == self.id
        self.childCategories.each do |ch|
          ch.relativeDepthSet(@relativeDepth+1)
          childrenArray << ch
          list.each do |sc|
            if sc.to_i == ch.id
              childrenArray.concat ch.childrenTree(list).uniq
            end
          end
        end
      end
    end
    childrenArray
  end

  def depth
    level = 1
    if !self.parentCategories.empty?
      highestLevel = level
      self.parentCategories.each do |p|
        if p.depth > highestLevel
          highestLevel = p.depth
        end
      end
      level += highestLevel
    end
    level
  end

  def siblings
    ArticleCategory.select { |ac| ac.depth == self.depth }
  end
end
