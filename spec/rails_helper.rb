ENV['RAILS_ENV'] ||= 'test'
require 'logger' unless defined?(::Logger)

require 'active_support'
require 'active_support/dependencies'
require 'active_support/lazy_load_hooks'

require_relative '../lib/redmine_depending_custom_fields/helpers/menu_helper'
if ActiveSupport::Dependencies.autoload_paths.frozen?
  ActiveSupport::Dependencies.autoload_paths = ActiveSupport::Dependencies.autoload_paths.dup
end
if ActiveSupport::Dependencies.autoload_once_paths.frozen?
  ActiveSupport::Dependencies.autoload_once_paths = ActiveSupport::Dependencies.autoload_once_paths.dup
end
if ActiveSupport.respond_to?(:on_load)
  ActiveSupport.on_load(:active_record) do
    singleton = ActiveRecord::Base.singleton_class
    unless singleton.method_defined?(:open)
      singleton.define_method(:open) { |_arg = nil| }
    end
    if defined?(ActiveRecord::Relation) && !ActiveRecord::Relation.method_defined?(:open)
      ActiveRecord::Relation.define_method(:open) { |_arg = nil| }
    end
  end
elsif defined?(ActiveRecord::Base)
  singleton = ActiveRecord::Base.singleton_class
  unless singleton.method_defined?(:open)
    singleton.define_method(:open) { |_arg = nil| }
  end
  if defined?(ActiveRecord::Relation) && !ActiveRecord::Relation.method_defined?(:open)
    ActiveRecord::Relation.define_method(:open) { |_arg = nil| }
  end
end
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
