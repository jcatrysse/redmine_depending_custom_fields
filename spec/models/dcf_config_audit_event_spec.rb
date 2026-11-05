require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::ConfigAuditEvent, type: :model do
  subject(:event) { described_class.new(action: 'add_value', status: 'success', created_at: Time.now) }

  it 'is valid with an action and an allowed status' do
    expect(event).to be_valid
  end

  it 'requires an action' do
    event.action = nil
    expect(event).not_to be_valid
  end

  it 'rejects an unknown status' do
    event.status = 'bogus'
    expect(event).not_to be_valid
  end

  it 'is append-only: updates raise' do
    event.save!
    event.changes_summary = 'tampered'
    expect { event.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'is append-only: destroys raise' do
    event.save!
    expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  # Full review of 2026-11-05 (project-pages-12): the readers project,
  # custom_field, acting_user and affected_child_field_ids_list had no caller
  # and are removed (was 'parses affected_child_field_ids JSON' and 'returns
  # [] for blank affected_child_field_ids'); the column keeps the JSON text.
  it 'stores affected_child_field_ids as JSON text and has no unused readers' do
    event.affected_child_field_ids = [7, 8].to_json
    event.save!
    expect(described_class.find(event.id).affected_child_field_ids).to eq('[7,8]')
    [:project, :custom_field, :acting_user, :affected_child_field_ids_list].each do |name|
      expect(described_class.method_defined?(name)).to be(false), name.to_s
    end
  end
end
