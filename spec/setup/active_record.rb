require 'active_record'
require 'lib/attr_encodable'

ActiveRecord::Base.include_root_in_json = false

ActiveRecord::Base.establish_connection({:adapter => 'sqlite3', :database => ':memory:', :pool => 5, :timeout => 5000})

class ::Permission < ActiveRecord::Base
  belongs_to :user

  def hello
    "World!"
  end
end

class ::User < ActiveRecord::Base
  has_many :permissions

  def foobar
    "baz"
  end
end

silence_stream(STDOUT) do
  ActiveRecord::Schema.define do
    create_table :permissions, :force => true do |t|
      t.belongs_to :user
      t.string :name
    end

    create_table :users, :force => true do |t|
      t.string   "login",              :limit => 48
      t.string   "email",              :limit => 128
      t.string   "first_name",         :limit => 32
      t.string   "last_name",          :limit => 32
      t.string   "encrypted_password", :limit => 60
      t.boolean  "developer",                         :default => false
      t.boolean  "admin",                          :default => false
      t.boolean  "password_set",                      :default => true
      t.boolean  "verified",                          :default => false
      t.datetime "created_at"
      t.datetime "updated_at"
      t.integer  "notifications"
    end
  end
end
