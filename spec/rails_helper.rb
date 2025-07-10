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

RSpec.configure do |config|
  config.fixture_path = File.expand_path('fixtures', __dir__)
  if config.fixture_path && Dir.exist?(config.fixture_path)
    config.global_fixtures = Dir[File.join(config.fixture_path, '*.yml')].map { |f| File.basename(f, '.yml').to_sym }
  end
  config.use_transactional_fixtures = true
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

require File.expand_path('../init', __dir__)
