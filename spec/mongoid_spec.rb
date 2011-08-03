require 'securerandom'
require 'setup/mongoid'
require 'lib/attr_encodable'

describe Encodable do
  it "should register a module under Mongoid" do
    defined? Mongoid::Encodable
  end

  before :each do
    @person = Person.create({
      :login => "flipsasser",
      :first_name => "flip",
      :last_name => "sasser",
      :email => "flip@foobar.com",
      :encrypted_password => ::SecureRandom.hex(30),
      :developer => true,
      :admin => true,
      :password_set => true,
      :verified => true,
      :notifications => 7
    })
    @person.authorizations.create(:name => "create_blog_posts")
    @person.authorizations.create(:name => "edit_blog_posts")

    # Reset the options for each test
    [Authorization, Person].each do |klass|
      klass.class_eval do
        @default_attributes = nil
        @encodable_whitelist_started = nil
        @renamed_encoded_attributes = nil
        @unencodable_attributes = nil
      end
    end
  end

  it "should favor whitelisting to blacklisting" do
    Person.unencodable_attributes.should == []
    Person.attr_unencodable 'foo', 'bar', 'baz'
    Person.unencodable_attributes.should == [:foo, :bar, :baz]
    Person.attr_encodable :id, :first_name
    Person.unencodable_attributes.map(&:to_s).should == ['foo', 'bar', 'baz'] + Person.fields.map(&:first) - ['id', 'first_name']
  end

  describe "at the parent model level" do
    it "should not mess with to_json unless when attr_encodable and attr_unencodable are not set" do
      @person.as_json == @person.attributes
    end

    it "should not mess with :include options" do
      @person.as_json(:include => :authorizations) == @person.attributes.merge(:authorizations => @person.authorizations.as_json)
    end

    it "should not mess with :methods options" do
      @person.as_json(:methods => :foobar) == @person.attributes.merge(:foobar => "baz")
    end

    it "should allow me to whitelist attributes" do
      Person.attr_encodable :login, :first_name, :last_name
      @person.as_json.should == @person.attributes.slice('login', 'first_name', 'last_name')
    end

    it "should allow me to blacklist attributes" do
      Person.attr_unencodable :login, :first_name, :last_name
      @person.as_json.should == @person.attributes.except('login', 'first_name', 'last_name')
    end

    # Of note is the INSANITY of ActiveRecord in that it applies :only / :except to :include as well. Which is
    # obviously insane. Similarly, it doesn't allow :methods to come along when :only is specified. Good god, what
    # a shame.
    it "should allow me to whitelist attributes without messing with :include" do
      Person.attr_encodable :login, :first_name, :last_name
      @person.as_json(:include => :authorizations).should == @person.attributes.slice('login', 'first_name', 'last_name').merge("authorizations" => @person.authorizations.map(&:as_json))
    end

    it "should allow me to blacklist attributes without messing with :include and :methods" do
      Person.attr_unencodable :login, :first_name, :last_name
      @person.as_json(:include => :authorizations, :methods => :foobar).should == @person.attributes.except('login', 'first_name', 'last_name').merge("authorizations" => @person.authorizations.map(&:as_json), :foobar => "baz")
    end

    it "should not screw with :include if it's a hash" do
      Person.attr_unencodable :login, :first_name, :last_name
      @person.as_json(:include => {:authorizations => {:methods => :hello, :except => :id}}, :methods => :foobar).should == @person.attributes.except('login', 'first_name', 'last_name').merge("authorizations" => @person.authorizations.map{ |p| p.as_json(:methods => :hello, :except => :id) }, :foobar => "baz")
    end
  end

  describe "at the child model level when the paren model has attr_encodable set" do
    before :each do
      Person.attr_encodable :login, :first_name, :last_name
    end

    it "should not mess with to_json unless when attr_encodable and attr_unencodable are not set on the child, but are on the parent" do
      @person.authorizations.as_json == @person.authorizations.map(&:attributes)
    end

    it "should not mess with :include options" do
      # This is testing that the implicit ban on the :id attribute from Person.attr_encodable is not
      # applying to serialization of authorizations
      @person.as_json(:include => :authorizations)["authorizations"].first["_id"].should_not be_nil
    end

    it "should inherit any attr_encodable options from the child model" do
      Person.attr_encodable :_id
      Authorization.attr_encodable :name
      as_json = @person.as_json(:include => :authorizations)
      as_json["authorizations"].first["_id"].should be_nil
      as_json["_id"].should_not be_nil
    end

    it "should allow me to whitelist attributes" do
      Person.attr_encodable :login, :first_name, :last_name
      @person.as_json.should == @person.attributes.slice('login', 'first_name', 'last_name')
    end

    # it "should allow me to blacklist attributes" do
    #   Person.attr_unencodable :login, :first_name, :last_name
    #   @person.as_json.should == @person.attributes.except('login', 'first_name', 'last_name')
    # end
  end

  it "should let me specify automatic includes as well as attributes" do
    Person.attr_encodable :login, :first_name, :_id, :authorizations
    @person.as_json.should == @person.attributes.slice('login', 'first_name', '_id').merge("authorizations" => @person.authorizations.map(&:as_json))
  end

  it "should let me specify methods as well as attributes" do
    Person.attr_encodable :login, :first_name, :_id, :foobar
    @person.as_json.should == @person.attributes.slice('login', 'first_name', '_id').merge(:foobar => "baz")
  end

  describe "reassigning" do
    it "should let me reassign attributes" do
      Person.attr_encodable :id => :identifier
      @person.as_json.should == {'identifier' => @person.id}
    end

    it "should let me reassign attributes alongside regular attributes" do
      Person.attr_encodable :login, :last_name, :_id => :identifier
      @person.as_json.should == {'identifier' => @person._id, 'login' => 'flipsasser', 'last_name' => 'sasser'}
    end

    it "should let me reassign multiple attributes with one delcaration" do
      Person.attr_encodable :_id => :identifier, :first_name => :foobar
      @person.as_json.should == {'identifier' => @person._id, 'foobar' => 'flip'}
    end

    it "should let me reassign :methods" do
      Person.attr_encodable :foobar => :w00t
      @person.as_json.should == {'w00t' => 'baz'}
    end

    it "should let me reassign :include" do
      Person.attr_encodable :authorizations => :deez_authorizations
      @person.as_json.should == {'deez_authorizations' => @person.authorizations.map(&:as_json)}
    end

    it "should let me specify a prefix to a set of attr_encodable's" do
      Person.attr_encodable :_id, :first_name, :foobar, :authorizations, :prefix => :t
      @person.as_json.should == {'t__id' => @person._id, 't_first_name' => @person.first_name, 't_foobar' => 'baz', 't_authorizations' => @person.authorizations.map(&:as_json)}
    end
  end

  it "should propagate down subclasses as well" do
    Person.attr_encodable :name
    class SubPerson < Person; end
    SubPerson.unencodable_attributes.should == Person.unencodable_attributes
  end
end
