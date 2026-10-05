ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../../config/environment', __dir__)
require 'rspec/rails'
begin
  require 'active_record/query_recorder'
rescue LoadError
end

unless defined?(ActiveRecord::QueryRecorder)
  class ActiveRecord::QueryRecorder
    attr_reader :count

    def initialize(&block)
      @count = 0
      recorder = self
      base = nil
      if defined?(CustomField)
        base = CustomField.singleton_class
        base.alias_method :_qr_orig_where, :where
        base.define_method(:where) do |*args, &blk|
          recorder.increment
          _qr_orig_where(*args, &blk)
        end
      end

      callback = lambda do |*_, payload|
        next if payload[:name] =~ /SCHEMA|CACHE/
        @count += 1
      end
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        yield
      end
    ensure
      if base
        base.alias_method :where, :_qr_orig_where
        base.remove_method :_qr_orig_where
      end
    end

    def increment
      @count += 1
    end
  end
end
require_relative 'support/custom_field_factory'
require_relative 'support/dcf_config_helpers'
require_relative 'support/query_counter'
require_relative 'support/dcf_large_list'
require_relative 'support/dcf_format_characterization'

RSpec.configure do |config|
  fixture_path = File.expand_path('fixtures', __dir__)

  if config.respond_to?(:fixture_paths=)
    config.fixture_paths = [fixture_path]
  elsif config.respond_to?(:fixture_path=)
    config.fixture_path = fixture_path
  end

  if Dir.exist?(fixture_path) && config.respond_to?(:global_fixtures=)
    config.global_fixtures = Dir[File.join(fixture_path, '*.yml')].map { |f| File.basename(f, '.yml').to_sym }
  end

  config.use_transactional_fixtures = true

  # Random order surfaces hidden dependencies between examples; the seed is
  # printed so a failure can be replayed with --seed <n>.
  config.order = :random
  Kernel.srand config.seed

  # Browser specs are opt-in (DCF_SYSTEM_SPECS=1), they need Chrome.
  if ENV['DCF_SYSTEM_SPECS'] == '1'
    require_relative 'support/system_driver'
  else
    config.filter_run_excluding type: :system
  end
  config.filter_run_excluding :mysql unless Redmine::Database.mysql?
  config.filter_run_excluding :perf unless ENV['DCF_PERF_SPECS'] == '1'

  # A spec that switches the locale must not leak it into the next example.
  config.around { |example| I18n.with_locale(I18n.default_locale) { example.run } }

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  begin
    require 'factory_bot'
    config.include FactoryBot::Syntax::Methods
  rescue LoadError
  end

  config.before(:each, type: :controller) do
    next unless defined?(User)

    user = instance_double(User, id: 1, admin?: true, logged?: true, login: 'test', language: 'en')
    allow(User).to receive(:current).and_return(user)
    @request.session[:user_id] = user.id if defined?(@request)
  end
end
