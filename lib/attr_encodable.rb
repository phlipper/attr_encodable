begin
  require "mongoid"
rescue LoadError => e
  nil
end

module Encodable

  module ClassMethods
    def attr_encodable(*attributes)
      prefix = begin
        if attributes.last.is_a?(Hash)
          attributes.last.assert_valid_keys(:prefix)
          prefix = attributes.extract_options![:prefix]
        end
      rescue ArgumentError
      end

      unless @encodable_whitelist_started
        encodable_attrs = if respond_to? :column_names
          column_names
        elsif respond_to? :fields
          fields.map &:first
        else
          []
        end

        # Since we're white-listing, make sure we black-list every attribute to begin with
        unencodable_attributes.push *encodable_attrs.map(&:to_sym)  # *column_names.map(&:to_sym)
        @encodable_whitelist_started = true
      end

      stash_encodable_attribute = lambda do |method, value|
        if prefix
          value = "#{prefix}_#{value}"
        end
        method = method.to_sym
        value = value.to_sym
        renamed_encoded_attributes.merge!({method => value}) if method != value
        # Un-black-list any attribute we white-listed
        unencodable_attributes.delete method
        default_attributes.push method
      end

      attributes.each do |attribute|
        if attribute.is_a?(Hash)
          attribute.each do |method, value|
            stash_encodable_attribute.call(method, value)
          end
        else
          stash_encodable_attribute.call(attribute, attribute)
        end
      end
    end

    def attr_unencodable(*attributes)
      unencodable_attributes.push *attributes.map(&:to_sym)
    end

    def default_attributes
      @default_attributes ||= begin
        default_attributes = []
        superk = superclass
        while superk.respond_to?(:default_attributes)
          default_attributes.push(*superk.default_attributes)
          superk = superk.superclass
        end
        default_attributes
      end
    end

    def renamed_encoded_attributes
      @renamed_encoded_attributes ||= begin
        renamed_encoded_attributes = {}
        superk = superclass
        while superk.respond_to?(:renamed_encoded_attributes)
          renamed_encoded_attributes.merge!(superk.renamed_encoded_attributes)
          superk = superk.superclass
        end
        renamed_encoded_attributes
      end
    end

    def unencodable_attributes
      @unencodable_attributes ||= begin
        unencodable_attributes = []
        superk = superclass
        while superk.respond_to?(:unencodable_attributes)
          unencodable_attributes.push(*superk.unencodable_attributes)
          superk = superk.superclass
        end
        unencodable_attributes
      end
    end
  end

  module InstanceMethods
    def serializable_hash(options = {})
      if options && options[:only]
        # We DON'T want to fuck with :only and :except showing up in the same call. This is a disaster.
        super
      else
        options ||= {}
        original_except = if options[:except]
          options[:except] = Array(options[:except]).map(&:to_sym)
        else
          options[:except] = []
        end

        # This is a little bit confusing. ActiveRecord's default behavior is to apply the :except arguments you pass
        # in to any :include options UNLESS it's overridden on the :include option. In the event that we have some
        # *default* excepts that come from Encodable, we want to ignore those and pass only whatever the original
        # :except options from the user were on down to the :include guys.
        inherited_except = original_except - self.class.default_attributes
        case options[:include]
        when Array, Symbol
          # Convert includes arrays or singleton symbols into a hash with our original_except scope
          includes = Array(options[:include])
          options[:include] = Hash[*includes.map{|association| [association, {:except => inherited_except}]}.flatten]
        else
          options[:include] ||= {}
        end

        # Exclude the black-list
        options[:except].push *self.class.unencodable_attributes

        encodable_attrs = if self.class.respond_to? :column_names
          self.class.column_names
        elsif self.class.respond_to? :fields
          self.class.fields.map(&:first)
        else
          []
        end

        # Include any default :include or :methods arguments that were passed in earlier
        self.class.default_attributes.each do |attribute, as|
          if association = self.class.reflect_on_association(attribute)
            options[:include][attribute] = {:except => inherited_except}
          elsif respond_to?(attribute) && !encodable_attrs.include?(attribute.to_s)
            options[:methods] ||= Array(options[:methods]).compact
            options[:methods].push attribute
          end
        end

        as_json = super(options)
        unless self.class.renamed_encoded_attributes.empty?
          self.class.renamed_encoded_attributes.each do |attribute, as|
            as_json[as.to_s] = as_json.delete(attribute) || as_json.delete(attribute.to_s)
          end
        end
        as_json
      end
    end
  end
end


if defined? ActiveRecord::Base
  ActiveRecord::Base.extend Encodable::ClassMethods
  ActiveRecord::Base.send :include, Encodable::InstanceMethods
end

if defined? Mongoid
  module Mongoid
    module Encodable
      def self.included(base)
        base.extend ::Encodable::ClassMethods
        base.send :include, ::Encodable::InstanceMethods
      end
    end
  end
end
