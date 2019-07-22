# Similar to ActiveRecord::Base, but records come from a user-provided function instead of a database table.
#
# Supports most of the ActiveRecord methods and semantics, including composable queries and scopes. However, all
# records are read-only.
#
# Synthetic models also allow setting context for a scope; this allows dependencies to be injected.
#
# Subclasses must implement two class-level functions: `load_by_id` and `all_ids`. See their definitions below
# for requirements.
class SyntheticModelBase
  include Draper::Decoratable

  class << self
    delegate(*SyntheticScope::AUTOMATIC_SCOPE_METHODS, to: :synthetic_scope)

    # Must be overridden by subclass. Should return a model instance, or nil
    def load_by_id(_id, _context)
      raise NotImplementedError
    end

    # Must be overridden by subclass. Should return an Array with every id that would make load_by_id return a record
    def all_ids(_context)
      raise NotImplementedError
    end

    # Returns an array of records with the given ids, in the same order.
    # May be overridden by subclass if it has an efficient way to load multiple ids in a batch
    def load_by_ids(ids, context)
      ids.map { |id| load_by_id(id, context) }
    end

    # Returns an array of hashes with keys matching the given columns and values from the rec with the given id.
    # May return nils in the array.
    # May return additional, unrequested columns in each hash.
    # May be overridden by subclass if it has a more efficient approach.
    def extract_by_ids(ids, columns, context)
      records = load_by_ids(ids, context).index_by(&:id)
      ids.map do |id|
        rec = records[id]
        next nil unless rec
        columns.map { |col| [col, rec.send(col)] }.to_h
      end
    end

    # Defines an item that can be provided in `with_context`
    def context_key(key)
      context_keys.push key
    end

    # Returns the list of context keys
    def context_keys
      @context_keys ||= []
    end

    # Defines a virtual "column" that will be represented by a field in the record
    def synthetic_column(name)
      name = name.to_sym
      raise "Column #{name.inspect} already configured" if synthetic_columns.include?(name)
      synthetic_columns.push name
      attr_reader name
    end

    # Returns the list of column names
    def synthetic_columns
      @columns ||= [:id]
    end

    def synthetic_scope
      SyntheticScope.new(self)
    end
  end

  attr_reader :id

  def initialize(**kwargs)
    raise "Id missing" unless kwargs.key?(:id)

    kwargs.each do |k, v|
      raise "No such column #{k.inspect}" unless self.class.synthetic_columns.include?(k)
      instance_variable_set(:"@#{k}", v)
    end
  end

  def ==(other)
    other.class == self.class && id == other.id
  end

  def inspect
    attr_values = self.class.synthetic_columns.map { |k| "#{k}: #{self.send(k).inspect}" }
    "#<#{self.class.name} #{attr_values.join(', ')}>"
  end
end
