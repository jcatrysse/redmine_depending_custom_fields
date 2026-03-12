require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::ParentDetector do
  let(:parent1) { instance_double(CustomField, id: 10, position: 1) }
  let(:parent2) { instance_double(CustomField, id: 12, position: 2) }
  let(:project)  { instance_double(Project) }
  let(:issue1)   { instance_double(Issue, project: project, available_custom_fields: [parent1, parent2]) }
  let(:issue2)   { instance_double(Issue, project: project, available_custom_fields: [parent1, parent2]) }

  before do
    allow(issue1).to receive(:available_custom_fields).and_return([parent1, parent2])
    allow(issue2).to receive(:available_custom_fields).and_return([parent1, parent2])
    allow(Rails.cache).to receive(:fetch).and_return({
      '31' => { parent_id: '10', map: {} },
      '32' => { parent_id: '12', map: {} }
    })
    allow(CustomField).to receive(:where).and_return([parent1, parent2])
    allow(parent1).to receive(:visible?).and_return(true)
    allow(parent1).to receive(:role_ids).and_return([])
    allow(parent2).to receive(:visible?).and_return(true)
    allow(parent2).to receive(:role_ids).and_return([])
  end

  it 'returns parent fields ordered by position' do
    result = described_class.for_issues([issue1, issue2])
    expect(result).to eq([parent1, parent2])
  end

  it 'excludes fields not available for all issues' do
    issue2 = instance_double(Issue, project: project, available_custom_fields: [parent1])
    result = described_class.for_issues([issue1, issue2])
    expect(result).to eq([parent1])
  end

  it 'excludes fields not visible to the user' do
    user = instance_double(User, admin?: false)
    allow(User).to receive(:current).and_return(user)
    allow(user).to receive(:roles_for_project).with(project).and_return([])

    allow(parent1).to receive(:visible?).and_return(false)
    allow(parent1).to receive(:role_ids).and_return([1])

    result = described_class.for_issues([issue1])
    expect(result).to eq([parent2])
  end


  it 'reads available custom fields once per issue' do
    described_class.for_issues([issue1, issue2])

    expect(issue1).to have_received(:available_custom_fields).once
    expect(issue2).to have_received(:available_custom_fields).once
  end

end
