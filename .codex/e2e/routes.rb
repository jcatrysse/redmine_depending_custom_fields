# Prints the GET paths this plugin adds or takes over, one per line, for
# smoke.mjs: routes to a controller defined in the plugin, and routes to a core
# controller whose action the plugin defines or overrides. Run by e2e.sh:
#   rails runner .codex/e2e/routes.rb <plugin_id>

root = Rails.root.join('plugins', ARGV.fetch(0)).to_s + '/'
Rails.application.eager_load!

def defined_in?(klass, method, root)
  return false unless klass.method_defined?(method) || klass.private_method_defined?(method)

  location = klass.instance_method(method).source_location
  location ? location.first.start_with?(root) : false
end

paths = Rails.application.routes.routes.filter_map do |route|
  next unless route.verb.to_s.split('|').include?('GET')

  controller = route.defaults[:controller]
  action = route.defaults[:action]
  next unless controller && action

  klass = "#{controller.camelize}Controller".safe_constantize
  next unless klass

  file = Object.const_source_location(klass.name)
  own = file ? file.first.start_with?(root) : false
  next unless own || defined_in?(klass, action.to_sym, root)

  route.path.spec.to_s
end
puts paths.uniq
