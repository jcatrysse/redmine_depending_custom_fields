require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::ExtendedUserFormat do
  let(:format) { described_class.instance }

  before do
    user = instance_double(User, id: 1, name: 'User1', status: User::STATUS_ACTIVE)
    relation = double('relation', first: user)
    allow(relation).to receive(:joins).and_return(relation)
    allow(relation).to receive(:where).and_return(relation)
    allow(relation).to receive(:distinct).and_return(relation)
    allow(relation).to receive(:to_a).and_return([user])
    allow(relation).to receive(:sorted).and_return([user])

    allow(User).to receive(:where).with(status: User::STATUS_ACTIVE).and_return(relation)
    allow(User).to receive(:all).and_return(relation)
    allow(User).to receive(:current).and_return(user)
    allow(User).to receive(:find_by_id).with(user.id).and_return(user)
  end

  describe 'format registration' do
    it 'registers the format' do
      RedmineDependingCustomFields.register_formats
      expect(Redmine::FieldFormat.available_formats).to include(
        RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER
      )
    end
  end

  describe '#possible_values_options' do
    let(:field) do
      UserCustomField.new(
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER,
        show_active: true,
        show_registered: false,
        show_locked: false,
        exclude_admins: false,
        only_project_members: false,
        group_ids: []
      )
    end

    it 'returns active users when show_active is enabled' do
      options = format.possible_values_options(field)
      ids = options.select { |o| o.is_a?(Array) && o[1].present? }.map { |o| o[1] }
      expect(ids).to include(User.where(status: User::STATUS_ACTIVE).first.id.to_s)
    end

    it 'filters by project members when enabled' do
      field.only_project_members = true
      project = instance_double(Project, id: 5)

      relation = User.all
      allow(relation).to receive(:where).with(status: [User::STATUS_ACTIVE]).and_return(relation)
      expect(relation).to receive(:joins).with(:members).and_return(relation)
      expect(relation).to receive(:where).with(members: { project_id: project.id }).and_return(relation)
      allow(relation).to receive(:distinct).and_return(relation)

      format.possible_values_options(field, instance_double(Issue, project: project))
    end

    it 'groups options by status' do
      field.show_locked = true
      options = format.possible_values_options(field)
      groups = options.select { |o| o.is_a?(Array) && o[2].is_a?(Hash) && o[2][:class] == 'option-group' }.map(&:first)
      expect(groups).to include(I18n.t(:status_active))
    end
  end

  describe '#query_filter_values' do
    let(:field) do
      UserCustomField.new(
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER,
        show_active: true,
        show_registered: false,
        show_locked: false,
        exclude_admins: false,
        only_project_members: false,
        group_ids: []
      )
    end

    it 'returns active users when show_active is enabled' do
      values = format.query_filter_values(field, nil)
      ids = values.map { |v| v[1] }
      expect(ids).to include(User.where(status: User::STATUS_ACTIVE).first.id.to_s)
    end
  end

  describe '#before_custom_field_save' do
    let(:field) do
      UserCustomField.new(
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER,
        show_active: nil,
        show_registered: nil,
        show_locked: nil,
        exclude_admins: nil,
        only_project_members: nil,
        group_ids: []
      )
    end

    it 'casts boolean attributes to false when nil' do
      format.before_custom_field_save(field)
      expect(field.show_active).to eq(false)
      expect(field.show_registered).to eq(false)
      expect(field.show_locked).to eq(false)
      expect(field.exclude_admins).to eq(false)
      expect(field.only_project_members).to eq(false)
    end
  end
end
