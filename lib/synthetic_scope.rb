# rubocop:disable Metrics/ClassLength
class SyntheticScope
  attr_reader :synthetic_model_class, :context, :filters, :orderings

  AUTOMATIC_SCOPE_METHODS = [:with_context, :all, :empty?, :find, :find_by_id, :merge, :none, :pluck, :where].freeze

  ### Foundational methods ###

  def initialize(synthetic_model_class, context: {}, filters: {}, orderings: [])
    unknown_context_keys = context.keys - synthetic_model_class.context_keys
    raise "Unknown context keys #{unknown_context_keys.inspect}" unless unknown_context_keys.empty?

    @synthetic_model_class = synthetic_model_class
    @context = OpenStruct.new(context)
    @filters = filters
    @orderings = normalize_orderings(orderings)
  end

  def deep_clone
    self.class.new(
      synthetic_model_class,
      context: context.to_h,
      filters: filters.deep_dup,
      orderings: orderings.deep_dup
    )
  end

  def ==(other)
    return false unless other.respond_to?(:to_a)
    self.to_a == other.to_a
  end

  def merge(other_scope)
    other_scope = other_scope.synthetic_scope # In case it's a plain SyntheticModel class
    raise "Other scope on wrong model" unless other_scope.synthetic_model_class == synthetic_model_class

    merged_scope = deep_clone
    other_scope.context.to_h.each { |key, val| merged_scope.context[key] = val }
    other_scope.filters.each { |key, val| (merged_scope.filters[key] ||= []).concat val }
    merged_scope.orderings.concat(other_scope.orderings)
    merged_scope
  end

  def method_missing(name, *args)
    if synthetic_model_class.respond_to?(name) && !SyntheticModelBase.respond_to?(name)
      result = synthetic_model_class.send(name, *args)
      # If it was a scope method, combine it with the current scope
      result.is_a?(SyntheticScope) ? merge(result) : result
    else
      super
    end
  end

  def synthetic_scope
    self
  end

  def with_context(**kwargs)
    merge(SyntheticScope.new(self.synthetic_model_class, context: kwargs))
  end

  ### Enumerable conformance ###

  def each(&block)
    load_all.each(&block)
  end

  include Enumerable

  ### ActiveRecord methods ###

  def all
    self
  end

  def empty?
    count == 0
  end

  def find(id)
    found_record = id_to_record(id)
    raise ActiveRecord::RecordNotFound unless found_record
    found_record
  end

  def find_by_id(id)
    id_to_record(id)
  end

  def ids
    available_ids
  end

  def none
    where(id: -> (_id) { false })
  end

  def order(*args)
    merge(SyntheticScope.new(self.synthetic_model_class, orderings: args))
  end

  def pluck(*columns)
    pluck_hashes(*columns).pluck(*columns) # Delegate to Enumerable#pluck
  end

  def pluck_hashes(*columns)
    assert_valid_columns!(columns)

    useful_columns = (columns + filters.keys + orderings.map(&:column)).uniq
    synthetic_model_class
      .extract_by_ids(ids, useful_columns, context)
      .compact
      .select { |row_hash| matches_record_filter?(row_hash) }
      .sort { |a, b| rec_cmp(a, b) }
      .map { |row_hash| row_hash.slice(*columns) }
  end

  def where(**kwargs)
    filters = kwargs.transform_keys(&:to_sym).transform_values { |v| [v] }
    merge(SyntheticScope.new(self.synthetic_model_class, filters: filters))
  end

  private

  def available_ids
    synthetic_model_class.all_ids(context).select { |id| matches_id_filter?(id) }
  end

  def load_all
    ids = available_ids
    synthetic_model_class
      .load_by_ids(ids, context)
      .select { |rec| matches_record_filter?(rec) }
      .sort { |a, b| rec_cmp(a, b) }
  end

  def id_to_record(id)
    return nil unless matches_id_filter?(id)
    found_record = synthetic_model_class.load_by_id(id, context)
    return nil unless found_record && matches_record_filter?(found_record)
    found_record
  end

  def matches_id_filter?(id)
    (filters[:id] || []).all? do |filter_value|
      matches_filter?(filter_value, id)
    end
  end

  def matches_record_filter?(rec)
    filters.all? do |key, filter_values|
      next true if key == :id
      filter_values.all? do |filter_value|
        rec_value = rec.is_a?(Hash) ? rec[key] : rec.send(key)
        matches_filter?(filter_value, rec_value)
      end
    end
  end

  def matches_filter?(filter_value, model_value)
    case filter_value
    when Array then filter_value.include? model_value
    when Proc then filter_value.call(model_value)
    else filter_value == model_value
    end
  end

  def rec_cmp(a, b)
    orderings.each do |ordering|
      a_value = a.is_a?(Hash) ? a[ordering.column] : a.send(ordering.column)
      b_value = b.is_a?(Hash) ? b[ordering.column] : b.send(ordering.column)
      cmp = a_value <=> b_value
      if cmp != 0
        cmp = -cmp if ordering.reverse
        return cmp
      end
    end

    0
  end

  Ordering = Struct.new(:column, :reverse)

  def normalize_orderings(args)
    args.flat_map do |arg|
      case arg
      when Ordering then [arg]
      when String, Symbol then [Ordering.new(arg.to_sym, false)]
      when Hash then arg.map { |col, direction| Ordering.new(col, direction == :desc) }
      else raise "Unable to interpret ordering argument #{arg.inspect}"
      end
    end
  end

  def assert_valid_columns!(columns)
    columns.each do |col|
      unless synthetic_model_class.synthetic_columns.include?(col)
        raise ActiveRecord::StatementInvalid.new("No such column #{col.inspect} to pluck")
      end
    end
  end
end
