# frozen_string_literal: true

require_relative '../rails_helper'
require 'open3'
require 'rake'
require 'rbconfig'

# WP-13 (limits design 7.1): Redmine loads every plugin rake file on every
# rake run, before the environment exists (db:create on a missing database
# included). Loading the file must therefore touch no database and no plugin
# constant; the tasks are thin wrappers that propagate the exit code. Each
# example loads the file into a fresh Rake application (a second load into
# the same one would add a second action to each task).
RSpec.describe 'lib/tasks/redmine_depending_custom_fields.rake' do
  fixtures :users

  let(:path) { File.expand_path('../../lib/tasks/redmine_depending_custom_fields.rake', __dir__) }
  let(:names) { %w[redmine:depending_custom_fields:report_sizes redmine:depending_custom_fields:widen_core_columns] }

  around do |example|
    original = Rake.application
    metadata = Rake::TaskManager.record_task_metadata
    Rake::TaskManager.record_task_metadata = true
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    example.run
  ensure
    Rake.application = original
    Rake::TaskManager.record_task_metadata = metadata
  end

  def sql_events(&block)
    events = []
    callback = ->(*, payload) { events << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    events
  end

  it 'loads without a query and without asking which database runs' do
    allow(Redmine::Database).to receive(:mysql?).and_call_original
    events = sql_events { load path }

    expect(events).to eq([])
    expect(Redmine::Database).not_to have_received(:mysql?)
  end

  it 'loads in a plain Ruby process without Rails or the plugin' do
    script = 'Rake::Task.define_task(:environment); load ARGV[0]; ' \
             'puts Rake::Task.tasks.map { |t| [t.name, *t.prerequisites].join(" ") }; ' \
             'puts "loaded=" + $LOADED_FEATURES.grep(%r{/lib/redmine_depending_custom_fields/}).inspect'
    output, status = Open3.capture2e(RbConfig.ruby, '-rrake', '-e', script, path)

    expect(status.exitstatus).to eq(0), output
    expect(output.lines.map(&:strip)).to include(*names.map { |name| "#{name} environment" }, 'loaded=[]')
  end

  it 'defines exactly the two tasks, each depending on :environment only' do
    load path
    defined = Rake::Task.tasks.map(&:name).grep(/depending_custom_fields/)

    expect(defined).to eq(names)
    names.each do |name|
      expect(Rake::Task[name].prerequisites).to eq(['environment'])
      expect(Rake::Task[name].comment).to be_present
      expect(Rake::Task[name].full_comment).not_to match(/[\u2013\u2014]/)
    end
  end

  {
    'redmine:depending_custom_fields:report_sizes' => 'RedmineDependingCustomFields::StorageReport',
    'redmine:depending_custom_fields:widen_core_columns' => 'RedmineDependingCustomFields::CoreColumnWidener'
  }.each do |name, class_name|
    describe name do
      let(:runner) { instance_double(class_name, run: 0) }

      before do
        load path
        allow(class_name.constantize).to receive(:from_env).and_return(runner)
      end

      it 'passes ENV and $stdout to the class and does not exit on 0' do
        expect { Rake::Task[name].invoke }.not_to raise_error
        expect(class_name.constantize).to have_received(:from_env).with(equal(ENV), out: $stdout)
      end

      it 'exits with the status the class returns' do
        allow(runner).to receive(:run).and_return(1)

        expect { Rake::Task[name].invoke }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        Rake::Task[name].reenable
        allow(runner).to receive(:run).and_return(0)
        expect { Rake::Task[name].invoke }.not_to raise_error
      end
    end
  end
end
