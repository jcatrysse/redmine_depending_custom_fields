# Performance probe, identical file in every perf checkout (config/initializers/zz_perf_probe.rb).
# Per request: SQL query count (without SCHEMA and CACHE), the numbers of the Rails "Completed" line (view and ActiveRecord
# runtime, allocations), GC heap_live_slots and objects allocated. Published as X-Perf-* response headers and appended as one
# JSON line to log/perf.log. Cost: a few counter increments per query and one small file append per request.
require 'json'

module PerfProbe
  KEY = :perf_probe
  LOG = Rails.root.join('log', 'perf.log')

  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      st = Thread.current[KEY] = { sql: 0 }
      alloc0 = GC.stat(:total_allocated_objects)
      cpu0 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      status, headers, body = @app.call(env)
      st[:alloc_total] = GC.stat(:total_allocated_objects) - alloc0
      st[:cpu_ms] = ((Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu0) * 1000).round(1)
      st[:heap_live_slots] = GC.stat(:heap_live_slots)
      headers['X-Perf-Sql'] = st[:sql].to_s
      headers['X-Perf-View'] = st[:view_ms].to_s
      headers['X-Perf-Db'] = st[:db_ms].to_s
      headers['X-Perf-Alloc'] = st[:allocations].to_s
      headers['X-Perf-Duration'] = st[:duration_ms].to_s
      headers['X-Perf-Alloc-Total'] = st[:alloc_total].to_s
      headers['X-Perf-Heap-Live'] = st[:heap_live_slots].to_s
      headers['X-Perf-Cpu'] = st[:cpu_ms].to_s
      begin
        File.open(LOG, 'a') { |f| f.puts(JSON.generate(st.merge(path: env['PATH_INFO'], method: env['REQUEST_METHOD'], status: status))) }
      rescue StandardError
        nil
      end
      [status, headers, body]
    end
  end
end

ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
  payload = args.last
  st = Thread.current[PerfProbe::KEY]
  next unless st
  next if payload[:name] == 'SCHEMA' || payload[:name] == 'CACHE' || payload[:cached]
  st[:sql] += 1
end

ActiveSupport::Notifications.subscribe('process_action.action_controller') do |event|
  st = Thread.current[PerfProbe::KEY]
  next unless st
  p = event.payload
  st[:view_ms] = (p[:view_runtime] || 0).round(1)
  st[:db_ms] = (p[:db_runtime] || 0).round(1)
  st[:duration_ms] = event.duration.round(1)
  st[:allocations] = event.allocations
  st[:controller_action] = "#{p[:controller]}##{p[:action]}"
end

Rails.application.config.middleware.insert_before 0, PerfProbe::Middleware
