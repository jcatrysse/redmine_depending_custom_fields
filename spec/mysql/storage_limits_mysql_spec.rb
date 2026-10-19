# frozen_string_literal: true

require_relative '../rails_helper'

# WP-11 (limits design 10.3, V1, V2): on a real MySQL/MariaDB server, without
# stubs. Excluded on other adapters (spec/rails_helper.rb). The report header,
# the widener SQL and the schema cache belong to WP-13
# (spec/mysql/core_column_widener_mysql_spec.rb).
RSpec.describe 'StorageLimits on MySQL', :mysql do
  fixtures :users

  let(:limits) { RedmineDependingCustomFields::StorageLimits }

  def mariadb?
    CustomField.connection.select_value('SELECT VERSION()').to_s.include?('MariaDB')
  end

  def list_field(bytes)
    IssueCustomField.new(name: "My-#{SecureRandom.hex(3)}", field_format: 'list', is_for_all: true,
                         possible_values: DcfLargeList.values_of_yaml_bytes(bytes))
  end

  it 'reads the real TEXT limit of both columns' do
    expect(limits.mysql?).to be(true)
    expect(CustomField.columns_hash['possible_values'].limit).to eq(65_535)
    expect(limits.column_limit('possible_values')).to eq(65_535)
    expect(limits.column_limit('format_store')).to eq(65_535)
  end

  it 'saves a 65,535-byte list and refuses 65,536 bytes with the model error' do
    fits = list_field(65_535)
    expect(fits.save).to be(true), fits.errors.full_messages.inspect
    expect(CustomField.where(id: fits.id).pick(Arel.sql('LENGTH(possible_values)'))).to eq(65_535)

    over = list_field(65_536)
    expect { expect(over.save).to be(false) }.not_to raise_error
    expect(over.errors.details[:possible_values].pluck(:error)).to eq([:dcf_storage_too_large])
    expect(over.errors.details[:possible_values].first).to include(bytes: 65_536, max_bytes: 65_535)
  end

  it 'leaves the database to refuse an oversized list saved without validation' do
    over = list_field(70_000)
    expect { over.save(validate: false) }.to raise_error(ActiveRecord::ValueTooLong)
  end

  # Strict mode refuses lost characters but only warns when the cut-off part
  # is trailing white space: MariaDB 10.11 drops the YAML's final newline of a
  # 65,536-byte list and stores 65,535 bytes. Not observed on MySQL here.
  it 'stores 65,536 bytes saved without the validation truncated on MariaDB' do
    skip 'observed on MariaDB 10.11 only' unless mariadb?

    over = list_field(65_536)
    expect(over.save(validate: false)).to be(true)
    expect(CustomField.where(id: over.id).pick(Arel.sql('LENGTH(possible_values)'))).to eq(65_535)
    stored = CustomField.connection.select_value(CustomField.where(id: over.id).select(:possible_values).to_sql)
    expect(stored).not_to end_with("\n")
    expect(CustomField.find(over.id).possible_values).to eq(over.possible_values)
  end

  # PC-15: such a row is dirty on every save (its stored YAML is not the
  # Rails dump) and its Rails dump does not fit, so every save is refused
  # and nothing is written.
  it 'refuses a rename of a list that MariaDB stored truncated' do
    skip 'observed on MariaDB 10.11 only' unless mariadb?

    over = list_field(65_536)
    over.save(validate: false)
    field = CustomField.find(over.id)
    name = field.name
    field.name = "#{name}-renamed"
    expect { expect(field.save).to be(false) }.not_to raise_error
    expect(field.errors.details[:possible_values].pluck(:error)).to eq([:dcf_storage_too_large])
    expect(field.errors.details[:possible_values].first).to include(bytes: 65_536, max_bytes: 65_535)
    expect(CustomField.where(id: over.id).pick(:name, Arel.sql('LENGTH(possible_values)'))).to eq([name, 65_535])
  end

  it 'shows the stored usage of a field at 90 percent of the real limit' do
    values = DcfLargeList.values_of_yaml_bytes(60_000)
    field = IssueCustomField.new(name: "Use-#{SecureRandom.hex(3)}", field_format: 'list', is_for_all: true,
                                 possible_values: values)
    field.save!
    rows = limits.usage(field)
    expect(rows.map(&:column)).to eq(['possible_values'])
    expect(rows.first.bytes).to eq(60_000)
    expect(rows.first.percent).to eq(91)
  end
end
