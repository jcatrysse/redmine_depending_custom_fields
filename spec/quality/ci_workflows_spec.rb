# frozen_string_literal: true

require_relative '../rails_helper'
require 'yaml'

# Owner rule: CI runs only when started manually (workflow_dispatch), never on
# push, pull_request or a schedule. Psych reads the YAML key `on` as boolean true.
RSpec.describe 'GitHub workflows' do
  workflows = Dir[File.expand_path('../../.github/workflows/*.{yml,yaml}', __dir__)].sort

  def triggers_of(doc)
    triggers = doc.key?('on') ? doc['on'] : doc[true]
    triggers.is_a?(Hash) ? triggers.keys.map(&:to_s) : Array(triggers).map(&:to_s)
  end

  it 'exist' do
    expect(workflows).not_to be_empty
  end

  it 'rejects a workflow that would also run on push' do
    doc = YAML.safe_load("on:\n  workflow_dispatch:\n  push:\n")
    expect(triggers_of(doc)).not_to eq(['workflow_dispatch'])
  end

  # WP-13 (UD-27): the optional MariaDB workflow is one of the guarded files.
  it 'include the manual MariaDB workflow' do
    expect(workflows.map { |path| File.basename(path) }).to include('rspec-mysql.yml')
  end

  workflows.each do |path|
    describe File.basename(path) do
      let(:doc) { YAML.safe_load(File.read(path)) }

      it 'is triggered by workflow_dispatch only' do
        expect(triggers_of(doc)).to eq(['workflow_dispatch'])
      end

      it 'grants read-only repository permissions' do
        expect(doc['permissions']).to eq('contents' => 'read')
      end

      it 'references no secrets' do
        expect(File.read(path)).not_to match(/\bsecrets\b/)
      end
    end
  end

  # The limits design 10.5 recipe on MariaDB for 5.1 and 7.0 in one dispatch
  # (UD-32 counts dispatches per workflow and SHA). A DATABASE_URL would
  # override database.yml, as the PostgreSQL workflows use it.
  describe 'rspec-mysql.yml' do
    let(:path) { File.expand_path('../../.github/workflows/rspec-mysql.yml', __dir__) }
    let(:source) { File.read(path) }
    let(:job) { YAML.safe_load(source)['jobs'].fetch('test') }

    it 'runs Redmine 5.1 and 7.0 on a MariaDB 10.11 service' do
      expect(job['services'].values.map { |service| service['image'] }).to eq(['mariadb:10.11'])
      expect(job['strategy']['matrix']['include']).to eq([{ 'redmine_branch' => '5.1-stable', 'ruby' => '3.2.5' },
                                                          { 'redmine_branch' => '7.0-stable', 'ruby' => '3.4.5' }])
    end

    it 'configures mysql2 without a PostgreSQL connection' do
      expect(source).not_to match(/DATABASE_URL|postgres|libpq|build\.pg/)
      expect(source).to include('adapter: mysql2', 'host: 127.0.0.1', 'encoding: utf8mb4', 'tx_isolation',
                                'rm -f db/schema.rb', 'libmariadb-dev')
    end

    it 'runs the specs and then the rake tasks in the recipe order' do
      lines = job['steps'].flat_map { |step| step['run'].to_s.lines.map(&:strip) }
      rakes = lines.grep(/\Abundle exec rake redmine:depending_custom_fields:/)
      recipe = ['report_sizes', 'widen_core_columns', 'widen_core_columns CONFIRM=1', 'report_sizes',
                'widen_core_columns REVERT=1 CONFIRM=1', 'report_sizes']

      expect(rakes).to eq(recipe.map { |task| "bundle exec rake redmine:depending_custom_fields:#{task}" })
      expect(lines.index { |line| line.start_with?('bundle exec rspec') }).to be < lines.index(rakes.first)
    end
  end
end
