require 'mongoid'
require 'lib/attr_encodable'

Mongoid.configure do |config|
  config.master = Mongo::Connection.new.db("attr_encodable")
end

class Authorization
  include Mongoid::Document
  include Mongoid::Encodable
  belongs_to :person
  field :name

  def hello
    "World!"
  end
end

class Person
  include Mongoid::Document
  include Mongoid::Encodable
  has_many :authorizations
  field :login
  field :email
  field :first_name
  field :last_name
  field :encrypted_password
  field :developer, :type => Boolean, :default => false
  field :admin, :type => Boolean, :default => false
  field :password_set, :type => Boolean, :default => false
  field :verified, :type => Boolean, :default => false
  field :notifications, :type => Integer

  def foobar
    "baz"
  end
end
