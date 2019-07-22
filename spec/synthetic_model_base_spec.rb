require 'rails_helper'

RSpec.describe SyntheticModelBase do
  class FruitService
    FRUIT = {
      red: :apple,
      orange: :orange,
      yellow: :banana,
      green: :avocado,
      blue: :blueberry,
      indigo: :plum,
      violet: :grape,
    }.freeze

    def lookup_fruit(color_name)
      FRUIT[color_name.to_sym].to_s
    end
  end

  class Color < SyntheticModelBase
    COLORS = [:red, :orange, :yellow, :green, :blue, :indigo, :violet].freeze

    synthetic_column :name
    synthetic_column :fruit
    synthetic_column :len

    context_key :fruit_service

    def self.load_by_id(id, context)
      return nil unless id >= 0 && id < COLORS.length
      name = COLORS[id].to_s
      Color.new(
        id: id,
        name: name,
        fruit: context.fruit_service.lookup_fruit(name),
        len: name.length
      )
    end

    def self.all_ids(_context)
      (0...COLORS.length).to_a
    end

    def self.last_three
      where(id: [4, 5, 6])
    end

    def self.evens
      where(id: [0, 2, 4, 6])
    end

    def self.odds
      where(id: [1, 3, 5])
    end
  end

  let(:contextified_color) { Color.with_context(fruit_service: FruitService.new) }

  let(:red) { contextified_color.find(0) }
  let(:orange) { contextified_color.find(1) }
  let(:yellow) { contextified_color.find(2) }
  let(:blue) { contextified_color.find(4) }

  describe 'methods with column names' do
    it 'return attribute values' do
      expect(red.name).to eq('red')
      expect(red.fruit).to eq('apple')
      expect(red.len).to eq(3)

      expect(orange.name).to eq('orange')
      expect(orange.fruit).to eq('orange')
      expect(orange.len).to eq(6)
    end
  end

  describe '#==' do
    subject { yellow == other }

    describe 'on same object' do
      let(:other) { yellow }
      it { is_expected.to be(true) }
    end

    describe 'on result of finding the same id' do
      let(:other) { contextified_color.find(2) }
      it { is_expected.to be(true) }
      it 'does not require that the objects be the same instance' do
        expect(other).not_to be(yellow)
      end
    end

    describe 'on another Color record' do
      let(:other) { orange }
      it { is_expected.to be(false) }
    end

    describe 'on something totally unrelated' do
      let(:other) { 37 }
      it { is_expected.to be(false) }
    end

    describe 'on nil' do
      let(:other) { nil }
      it { is_expected.to be(false) }
    end
  end

  describe '#inspect' do
    subject { yellow.inspect }

    it { is_expected.to eq "#<Color id: 2, name: \"yellow\", fruit: \"banana\", len: 6>" }
  end

  describe '::all' do
    let(:scope) { contextified_color }
    subject { scope.all }

    it { is_expected.to eq(contextified_color.ids.map { |id| contextified_color.find(id) }) }

    describe 'on a limited scope' do
      let(:scope) { contextified_color.last_three }
      it { is_expected.to eq([4, 5, 6].map { |id| contextified_color.find(id) }) }
    end

    describe 'on a combined scope' do
      let(:scope) { contextified_color.last_three.evens }
      it { is_expected.to eq([4, 6].map { |id| contextified_color.find(id) }) }
    end

    describe 'on a self-contradictory scope' do
      let(:scope) { contextified_color.odds.evens }
      it { is_expected.to be_empty }
    end
  end

  describe '::empty?' do
    let(:scope) { contextified_color }
    subject { scope.empty? }

    it { is_expected.to be(false) }

    describe 'on a limited scope' do
      let(:scope) { contextified_color.last_three }
      it { is_expected.to be(false) }
    end

    describe 'on the ::none scope' do
      let(:scope) { contextified_color.none }
      it { is_expected.to be(true) }
    end

    describe 'on a scope with restrictions that exclude every record' do
      let(:scope) { contextified_color.where(id: 97) }
      it { is_expected.to be(true) }
    end
  end

  describe '::find' do
    subject { contextified_color.find(id) }

    describe 'on a valid id' do
      let(:id) { 2 }
      it { is_expected.to eq(yellow) }
    end

    describe 'on an invalid id' do
      let(:id) { 87 }
      it { is_expected_to_raise ActiveRecord::RecordNotFound }
    end
  end

  describe '::find_by_id' do
    let(:scope) { contextified_color }
    subject { scope.find_by_id(id) }

    describe 'on a valid id' do
      let(:id) { 2 }
      it { is_expected.to eq(yellow) }
    end

    describe 'on an invalid id' do
      let(:id) { 87 }
      it { is_expected.to be_nil }
    end

    describe 'on a filtered scope' do
      let(:scope) { contextified_color.last_three }

      describe 'on an id that is included in the scope' do
        let(:id) { 4 }
        it { is_expected.to eq(blue) }
      end

      describe 'on an id that is not included in the scope' do
        let(:id) { 2 }
        it { is_expected.to be_nil }
      end
    end
  end

  describe '::merge' do
    subject { scope.merge(other_scope) }

    describe 'given two unfiltered scopes' do
      let(:scope) { contextified_color }
      let(:other_scope) { contextified_color }
      it { is_expected.to eq(contextified_color.all) }
      it { is_expected.not_to eq(contextified_color.last_three) } # Check against false positives on scope#==
    end

    describe 'given two identical scopes' do
      let(:scope) { contextified_color.evens }
      let(:other_scope) { contextified_color.evens }
      it { is_expected.to eq(contextified_color.evens) }
    end

    describe 'given two scopes with an intersection' do
      let(:scope) { contextified_color.odds }
      let(:other_scope) { contextified_color.last_three }
      it { is_expected.to eq(contextified_color.where(id: 5)) }
    end

    describe 'given two scopes without an intersection' do
      let(:scope) { contextified_color.odds }
      let(:other_scope) { contextified_color.evens }
      it { is_expected.to eq(contextified_color.none) }
    end
  end

  describe '::none' do
    let(:scope) { contextified_color }
    subject { scope.none }

    it { is_expected.to be_empty }

    describe 'on a limited scope' do
      let(:scope) { contextified_color.last_three }
      it { is_expected.to be_empty }
    end
  end

  describe '::where' do
    subject { contextified_color.where(**conditions) }

    describe 'filtering on a single id' do
      let(:conditions) { { id: 3 } }
      it { is_expected.to eq([contextified_color.find(3)]) }
    end

    describe 'filtering on multiple ids' do
      let(:conditions) { { id: [1, 4] } }
      it { is_expected.to eq([contextified_color.find(1), contextified_color.find(4)]) }
    end

    describe 'filtering on a single field value' do
      let(:conditions) { { name: "orange" } }
      it { is_expected.to eq([orange]) }
    end

    describe 'filtering on a multiple field values' do
      let(:conditions) { { name: %w(orange blue) } }
      it { is_expected.to eq([orange, blue]) }
    end

    describe 'filtering on a mix of fields' do
      let(:conditions) { { id: [1, 3, 4], name: %w(yellow orange blue) } }
      it { is_expected.to eq([orange, blue]) }

      describe 'using sequential where calls' do
        subject { contextified_color.where(id: [1, 3, 4]).where(name: %w(yellow orange blue)) }
        it { is_expected.to eq([orange, blue]) }
      end
    end
  end

  describe '::order' do
    sorted_names = %w(blue green indigo orange red violet yellow)
    sorted_name_fruits = %w(blueberry avocado plum orange apple grape banana)
    length_ordered_names = %w(indigo orange violet yellow green blue red)

    specify 'ordering by a single column' do
      scope = contextified_color.order(:name)
      expect(scope.map(&:name)).to eq(sorted_names)
      expect(scope.pluck(:name)).to eq(sorted_names)
      expect(scope.pluck(:fruit)).to eq(sorted_name_fruits)
    end

    specify 'ordering by a single column in explicit ascending order' do
      scope = contextified_color.order(name: :asc)
      expect(scope.map(&:name)).to eq(sorted_names)
      expect(scope.pluck(:name)).to eq(sorted_names)
      expect(scope.pluck(:fruit)).to eq(sorted_name_fruits)
    end

    specify 'ordering by a single column in reverse' do
      scope = contextified_color.order(name: :desc)
      expect(scope.map(&:name)).to eq(sorted_names.reverse)
      expect(scope.pluck(:name)).to eq(sorted_names.reverse)
      expect(scope.pluck(:fruit)).to eq(sorted_name_fruits.reverse)
    end

    specify 'ordering by multiple columns' do
      scope = contextified_color.order({ len: :desc }, :name)
      expect(scope.map(&:name)).to eq(length_ordered_names)
      expect(scope.pluck(:name)).to eq(length_ordered_names)
    end
  end

  describe '::pluck' do
    subject { contextified_color.odds.pluck(*columns) }

    describe 'given a single column' do
      let(:columns) { [:id] }
      it { is_expected.to eq([1, 3, 5]) }
    end

    describe 'given multiple columns' do
      let(:columns) { [:id, :name] }
      it { is_expected.to eq([[1, 'orange'], [3, 'green'], [5, 'indigo']]) }
    end

    describe 'given multiple columns in a different sequence' do
      let(:columns) { [:name, :id] }
      it { is_expected.to eq([['orange', 1], ['green', 3], ['indigo', 5]]) }
    end

    describe 'given an invalid column' do
      let(:columns) { [:flavor] }
      it { is_expected_to_raise ActiveRecord::StatementInvalid }
    end

    describe 'given a combination of valid and invalid columns' do
      let(:columns) { [:id, :flavor] }
      it { is_expected_to_raise ActiveRecord::StatementInvalid }
    end
  end

  specify '::pluck with custom implementation' do
    animal_class = Class.new(SyntheticModelBase) do
      ANIMALS = %w(horse chicken monkey bear).freeze

      synthetic_column :len
      synthetic_column :even

      def self.all_ids(_context)
        ANIMALS
      end

      def self.load_by_id(id, _context)
        return nil unless ANIMALS.include?(id)
        new(id: id, len: id.length, even: id.length.even?)
      end

      def self.extract_by_ids(ids, columns, _context)
        return super unless (columns - [:id, :len]).empty?
        ids.map do |id|
          # Deliberately incorrect len so we can make sure this method is being called
          { id: id, len: 99 }
        end
      end
    end

    ids = %w(horse chicken monkey).freeze
    scope = animal_class.where(id: ids)

    # Using the deliberately incorrect custom extractor
    expect(scope.pluck(:id)).to eq(ids)
    expect(scope.pluck(:len)).to eq([99, 99, 99])
    expect(scope.pluck_hashes(:len)).to eq([{ len: 99 }, { len: 99 }, { len: 99 }])
    expect(scope.pluck(:id, :len)).to eq([["horse", 99], ["chicken", 99], ["monkey", 99]])
    expect(scope.pluck_hashes(:id, :len)).to eq(
      [
        { id: "horse", len: 99 },
        { id: "chicken", len: 99 },
        { id: "monkey", len: 99 },
      ]
    )

    # Falling back to the default extractor
    expect(scope.pluck(:len, :even)).to eq([[5, false], [7, false], [6, true]])
    expect(scope.where(even: false).pluck(:len, :even)).to eq([[5, false], [7, false]])
    expect(scope.pluck(:id, :len, :even)).to eq(
      [
        ["horse", 5, false],
        ["chicken", 7, false],
        ["monkey", 6, true],
      ]
    )
    expect(scope.pluck_hashes(:id, :len, :even)).to eq(
      [
        { id: "horse", len: 5, even: false },
        { id: "chicken", len: 7, even: false },
        { id: "monkey", len: 6, even: true },
      ]
    )
    # expect(scope.where(even: false).pluck(:id)).to eq(%w(horse chicken))
  end
end
