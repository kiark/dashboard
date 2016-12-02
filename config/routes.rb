Rails.application.routes.draw do
  resources :orders
  resources :items
  resources :transport_documents
  resources :companies
  resources :article_categories
  resources :articles
  resources :people
  devise_for :users
  # devise_scope :user do
  #   root "devise/sessions#new"
  # end
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  root 'home#dashboard'

  get    '/admin/users', to: 'users#index', as: :users_admin
  post   '/admin/users', to: 'users#create', as: :create_user_admin
  get    '/admin/users/new', to: 'users#new', as: :new_user_admin
  get    '/admin/users/:id/edit', to: 'users#edit', as: :edit_user_admin
  get    '/admin/users/:id', to: 'users#show', as: :show_user_admin
  patch  '/admin/users/:id', to: 'users#update', as: :update_user_admin
  put    '/admin/users/:id', to: 'users#update'
  delete '/admin/users/:id', to: 'users#delete', as: :delete_user_admin

  post '/users/:id/roles/:role', to: 'users#add_role'
  delete '/users/:id/roles/:role', to: 'users#rem_role'

  get    '/storage', to: 'storage#home', as: :storage
  get    '/incomplete_articles', to: 'articles#incomplete', as: :incomplete_articles
  post   '/article_categories/manage', to: 'article_categories#manage', as: :manage_article_categories
  post   '/article/categories/', to: 'articles#list_categories', as: :list_article_categories

  get    '/items_from_order/:order', to: 'items#from_order', as: :items_from_order
  get    '/items_new_order', to: 'items#new_order', as: :items_new_order

  post   '/items_new_order', to: 'orders#add_item_to_new_order', as: :add_item_to_order

end
