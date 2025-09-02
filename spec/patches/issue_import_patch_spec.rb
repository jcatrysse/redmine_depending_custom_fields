require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::Patches::IssueImportPatch do
  class DummyIssueImport
    def initialize(project, cfv)
      @project = project
      @cfv = cfv
    end

    def row_value(row, token)
      row[token]
    end

    def build_object(_row, _item)
      Struct.new(:project, :custom_field_values).new(@project, [@cfv])
    end
  end

  before do
    DummyIssueImport.prepend described_class
  end

  it 'assigns extended user values outside the project based on full name' do
    user = Struct.new(:id, :name).new(42, 'Jane Doe')
    user_class = Class.new do
      define_singleton_method(:all) do
        [user]
      end

      define_singleton_method(:find_by_id) do |id|
        id == 42 ? user : nil
      end
    end
    stub_const('User', user_class)

    principal_module = Module.new do
      def self.detect_by_keyword(users, keyword)
        users.find { |u| u.name == keyword }
      end
    end
    stub_const('Principal', principal_module)

    cf = instance_double('CustomField', id: 1, field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER, multiple?: false)
    cfv = Struct.new(:custom_field, :value).new(cf, nil)
    project = instance_double('Project', users: [])
    importer = DummyIssueImport.new(project, cfv)

    importer.build_object({ 'cf_1' => 'Jane Doe' }, nil)

    expect(cfv.value).to eq('42')
  end
end
