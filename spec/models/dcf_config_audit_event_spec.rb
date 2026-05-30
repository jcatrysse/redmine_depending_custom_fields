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

  it 'parses affected_child_field_ids JSON' do
    event.affected_child_field_ids = [7, 8].to_json
    expect(event.affected_child_field_ids_list).to eq([7, 8])
  end

  it 'returns [] for blank affected_child_field_ids' do
    event.affected_child_field_ids = nil
    expect(event.affected_child_field_ids_list).to eq([])
  end
end
