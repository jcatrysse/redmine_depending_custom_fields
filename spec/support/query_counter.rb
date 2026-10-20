# frozen_string_literal: true

# Counting helpers for performance assertions (gate G6). Later work packages
# assert invariance ("the same number of queries with 3 or 300 values") or a
# difference against a baseline, never absolute wall-clock times.
module DcfQueryCounter
  IGNORED = /\A(?:SCHEMA|CACHE|TRANSACTION)\z/.freeze

  # Counts the YAML deserializations of serialized store columns (format_store)
  # and records their inputs while a payload log is set.
  module YamlLoadSpy
    def load(yaml)
      counter = Thread.current[:dcf_yaml_loads]
      counter[0] += 1 if counter
      # WP-16: records the YAML payloads for the SP-20d check of
      # spec/requests/issue_form_contract_spec.rb.
      log = Thread.current[:dcf_yaml_payloads]
      log << yaml if log
      super
    end
  end

  # Number of SQL statements the block runs (schema, cache and transaction
  # statements excluded).
  def dcf_count_queries(&block)
    count = 0
    callback = lambda do |*, payload|
      count += 1 unless payload[:name].to_s.match?(IGNORED) || payload[:sql].to_s.match?(/\A\s*(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    count
  end

  # Number of ActiveRecord::Store::IndifferentCoder#load calls in the block.
  def dcf_count_yaml_loads
    previous = Thread.current[:dcf_yaml_loads]
    Thread.current[:dcf_yaml_loads] = [0]
    yield
    Thread.current[:dcf_yaml_loads][0]
  ensure
    Thread.current[:dcf_yaml_loads] = previous
  end

  # WP-16: records the YAML payloads for the SP-20d check of
  # spec/requests/issue_form_contract_spec.rb. The YAML strings
  # ActiveRecord::Store::IndifferentCoder#load received in the block, blank
  # inputs (Rails 7.1+ also passes them) left out.
  def dcf_yaml_payloads
    previous = Thread.current[:dcf_yaml_payloads]
    log = []
    Thread.current[:dcf_yaml_payloads] = log
    yield
    log.reject { |yaml| yaml.to_s.strip.empty? }
  ensure
    Thread.current[:dcf_yaml_payloads] = previous
  end

  # Extra queries the plugin adds: queries(with) - queries(without).
  def dcf_plugin_overhead(with:, without:)
    dcf_count_queries(&with) - dcf_count_queries(&without)
  end
end

ActiveRecord::Store::IndifferentCoder.prepend(DcfQueryCounter::YamlLoadSpy)

RSpec.configure do |config|
  config.include DcfQueryCounter
end
