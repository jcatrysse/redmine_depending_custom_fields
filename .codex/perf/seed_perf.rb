# frozen_string_literal: true

# Seeds the performance data sets with the MAIN plugin data model (0.0.15).
# Run inside a checkout:  RAILS_ENV=development bundle exec rails runner seed_perf.rb <ids.json>
# Deterministic (fixed random seed), bulk inserts for issues and custom values, verification through the models.
#
# Main data model: a depending field stores parent_custom_field_id, value_dependencies ({parent value => [child values]},
# enumerations: ids as strings) and default_value_dependencies in custom_fields.format_store (serialized Hash).
require 'json'

ActionMailer::Base.perform_deliveries = false
OUT = ARGV[0] || 'ids.json'
RNG = Random.new(20260101)
T0 = Time.now
def log(msg)
  puts("[seed #{(Time.now - T0).round(1)}s] #{msg}")
end

ADMIN_PASSWORD = 'admin123!'
MEMBER_PASSWORD = 'Passw0rd!x'
IDS = { 'redmine' => Redmine::VERSION.to_s, 'fields' => {}, 'projects' => {}, 'issues' => {}, 'users' => {},
        'values' => {}, 'counts' => {} }

# ----------------------------------------------------------------- settings and users
Setting.default_language = 'en'
Setting.login_required = '0'
Setting.plugin_redmine_depending_custom_fields = (Setting.plugin_redmine_depending_custom_fields || {}).merge(
  'manage_standard_custom_fields' => '1', 'block_removal_when_used' => '0'
)

manager_role = Role.find_by!(name: 'Manager')
manager_role.add_permission!(:manage_project_custom_field_configuration)

def upsert_user(login, first, last, password, admin: false)
  u = User.find_by(login: login) || User.new(login: login)
  u.firstname = first
  u.lastname = last
  u.mail = "#{login}@example.net" if u.mail.blank?
  u.admin = admin
  u.status = User::STATUS_ACTIVE
  u.language = 'en'
  u.password = password
  u.password_confirmation = password
  u.must_change_passwd = false
  u.mail_notification = 'none'
  u.save!
  u
end
admin = upsert_user('admin', 'Redmine', 'Admin', ADMIN_PASSWORD, admin: true)
member = upsert_user('perfmember', 'Perf', 'Member', MEMBER_PASSWORD)
User.current = admin
IDS['users'] = { 'admin' => { 'id' => admin.id, 'login' => 'admin', 'password' => ADMIN_PASSWORD },
                 'member' => { 'id' => member.id, 'login' => 'perfmember', 'password' => MEMBER_PASSWORD } }

bug = Tracker.find_by!(name: 'Bug')
feature = Tracker.find_by!(name: 'Feature')
status_new = IssueStatus.find_by!(name: 'New')
status_prog = IssueStatus.find_by!(name: 'In Progress')
priority = IssuePriority.find_by(is_default: true) || IssuePriority.first

def make_project(name, identifier, trackers)
  p = Project.find_by(identifier: identifier) || Project.new(identifier: identifier)
  p.name = name
  p.is_public = false
  p.enabled_module_names = %w[issue_tracking]
  p.trackers = trackers
  p.save!
  p
end
s1_projects = [make_project('Perf Typical A', 'perf-a', [bug, feature]),
               make_project('Perf Typical B', 'perf-b', [bug, feature]),
               make_project('Perf Typical C', 'perf-c', [bug, feature])]
large = make_project('Perf Large', 'perf-large', [feature])
baseline = make_project('Perf Baseline', 'perf-baseline', [feature])
(s1_projects + [large, baseline]).each do |pr|
  m = Member.find_by(user_id: member.id, project_id: pr.id) || Member.new(principal: member, project: pr)
  m.roles = [manager_role]
  m.save!
  IDS['projects'][pr.identifier] = pr.id
end
log 'projects and users ready'

# ----------------------------------------------------------------- fields
def make_field(name, format, projects:, trackers:, values: nil, parent: nil, multiple: false, mapping: nil, defaults: nil)
  cf = IssueCustomField.new(name: name)
  cf.field_format = format
  cf.multiple = multiple
  cf.is_required = false
  cf.visible = true
  cf.is_for_all = false
  cf.is_filter = true
  cf.possible_values = values if values
  cf.parent_custom_field_id = parent.id if parent
  cf.value_dependencies = mapping if mapping
  cf.default_value_dependencies = defaults if defaults
  cf.tracker_ids = trackers.map(&:id)
  cf.project_ids = projects.map(&:id)
  cf.save!
  IDS['fields'][name] = { 'id' => cf.id, 'format' => format, 'multiple' => multiple, 'parent_id' => cf.parent_custom_field_id }
  cf
end

both = [bug, feature]
# Hierarchies are generated: names are unique over the whole list.
countries = %w[Belgium Netherlands France Germany Spain Italy]
cities = countries.to_h { |c| [c, (1..5).map { |k| "#{c} City #{k}" }] }
districts = cities.values.flatten.to_h { |c| [c, (1..2).map { |k| "#{c} District #{k}" }] }
langs = countries.to_h { |c| [c, (1..2).map { |k| "#{c} Lang #{k}" }] }

t = Time.now
country = make_field('Country', 'list', values: countries, projects: s1_projects, trackers: both)
city = make_field('City', 'depending_list', values: cities.values.flatten, parent: country, mapping: cities,
                  defaults: countries.to_h { |c| [c, cities[c].first] }, projects: s1_projects, trackers: both)
district = make_field('District', 'depending_list', values: districts.values.flatten, parent: city, mapping: districts,
                      projects: s1_projects, trackers: both)
languages = make_field('Languages', 'depending_list', values: langs.values.flatten, parent: country, multiple: true,
                       mapping: langs, projects: s1_projects, trackers: both)
zone = make_field('Zone', 'enumeration', projects: s1_projects, trackers: both)
zones = (1..4).map { |k| CustomFieldEnumeration.create!(custom_field_id: zone.id, name: "Zone #{k}", position: k, active: true) }
site = make_field('Site', 'depending_enumeration', parent: zone, projects: s1_projects, trackers: both)
sites_by_zone = {}
zones.each_with_index do |z, zi|
  sites_by_zone[z.id.to_s] = (1..5).map do |k|
    CustomFieldEnumeration.create!(custom_field_id: site.id, name: "#{z.name} Site #{k}", position: zi * 5 + k, active: true).id.to_s
  end
end
site.value_dependencies = sites_by_zone
site.default_value_dependencies = zones.to_h { |z| [z.id.to_s, sites_by_zone[z.id.to_s].first] }
site.save!
severity = make_field('Severity', 'list', values: %w[Low Medium High Critical Blocker], projects: s1_projects, trackers: both)
customer = make_field('Customer', 'string', projects: s1_projects, trackers: both)
log "S1 fields ready (#{(Time.now - t).round(1)}s)"

# S2: 500 assemblies, 25,000 parts (50 each); plain 25,000 value list as core baseline in its own project.
t = Time.now
assemblies = (1..500).map { |i| format('A%03d', i) }
part_map = assemblies.to_h { |a| [a, (1..50).map { |k| format('%s-P%02d', a, k) }] }
assembly = make_field('Assembly', 'list', values: assemblies, projects: [large], trackers: [feature])
part = make_field('Part', 'depending_list', values: part_map.values.flatten, parent: assembly, mapping: part_map,
                  defaults: assemblies.to_h { |a| [a, part_map[a].first] }, projects: [large], trackers: [feature])
plain_values = (1..25_000).map { |i| format('Plain-%05d', i) }
plain = make_field('Plain25k', 'list', values: plain_values, projects: [baseline], trackers: [feature])
log "S2 fields ready (#{(Time.now - t).round(1)}s): Part=#{part.possible_values.size} values, mapping #{part.value_dependencies.size} parents"

# ----------------------------------------------------------------- bulk issues
def pick(arr)
  arr[RNG.rand(arr.size)]
end

def bulk_insert_issues(specs, author:, status_pool:, priority:)
  base = Time.now.utc - 86_400 * 90
  rows = specs.each_with_index.map do |s, i|
    ts = base + i * 600
    { tracker_id: s[:tracker].id, project_id: s[:project].id, subject: s[:subject], description: "Perf issue #{s[:subject]}",
      status_id: status_pool[i % status_pool.size].id, priority_id: priority.id, author_id: author.id,
      created_on: ts, updated_on: ts, done_ratio: 0, is_private: false, lock_version: 0 }
  end
  ids = rows.each_slice(500).flat_map { |chunk| Issue.insert_all(chunk, returning: %w[id]).rows.flatten }
  Issue.where(id: ids).update_all('root_id = id, lft = 1, rgt = 2')
  cv = []
  specs.each_with_index do |s, i|
    s[:values].each do |cf, v|
      vals = v.is_a?(Array) ? v : [v]
      vals = [''] if vals.empty?
      vals.each { |x| cv << { customized_type: 'Issue', customized_id: ids[i], custom_field_id: cf.id, value: x.to_s } }
    end
  end
  cv.each_slice(2000) { |chunk| CustomValue.insert_all(chunk) }
  ids
end

# S1: 300 issues over three projects, trackers alternate.
s1_specs = []
fixed = {
  'show' => { 'country' => 'Belgium', 'city' => 'Belgium City 1', 'district' => 'Belgium City 1 District 1',
              'langs' => ['Belgium Lang 1', 'Belgium Lang 2'], 'zone' => 0, 'site' => 0 },
  'update' => { 'country' => 'Belgium', 'city' => 'Belgium City 2', 'district' => 'Belgium City 2 District 1',
                'langs' => ['Belgium Lang 1'], 'zone' => 0, 'site' => 1 }
}
300.times do |i|
  pr = s1_projects[i % 3]
  tr = (i / 3).even? ? bug : feature
  c = pick(countries)
  ci = RNG.rand < 0.92 ? pick(cities[c]) : nil
  di = ci && RNG.rand < 0.8 ? pick(districts[ci]) : nil
  ls = RNG.rand < 0.7 ? langs[c].sample(1 + RNG.rand(2), random: RNG) : []
  zi = RNG.rand(4)
  si = RNG.rand < 0.85 ? pick(sites_by_zone[zones[zi].id.to_s]) : nil
  s1_specs << { project: pr, tracker: tr, subject: format('S1 issue %03d', i + 1),
                values: { country => c, city => ci.to_s, district => di.to_s, languages => ls, zone => zones[zi].id.to_s,
                          site => si.to_s, severity => pick(%w[Low Medium High Critical Blocker]),
                          customer => "Customer #{RNG.rand(40)}" } }
end
# Two dedicated issues in perf-a / Bug: the one shown and edited, the one updated by PATCH.
bug_a = s1_specs.each_index.select { |i| s1_specs[i][:project] == s1_projects[0] && s1_specs[i][:tracker] == bug }
{ 'show' => bug_a[0], 'update' => bug_a[1] }.each do |kind, idx|
  f = fixed[kind]
  s1_specs[idx][:subject] = "S1 #{kind} target"
  s1_specs[idx][:values] = { country => f['country'], city => f['city'], district => f['district'], languages => f['langs'],
                             zone => zones[f['zone']].id.to_s, site => sites_by_zone[zones[f['zone']].id.to_s][f['site']],
                             severity => 'Medium', customer => 'Customer fixed' }
end
s1_ids = bulk_insert_issues(s1_specs, author: admin, status_pool: [status_new, status_prog], priority: priority)
log "S1: #{s1_ids.size} issues"

# S2: 2000 issues in perf-large; dedicated show and update targets; baseline project 50 issues.
s2_specs = []
2000.times do |i|
  a = pick(assemblies)
  s2_specs << { project: large, tracker: feature, subject: format('S2 issue %04d', i + 1),
                values: { assembly => a, part => (RNG.rand < 0.97 ? pick(part_map[a]) : '') } }
end
s2_specs[0] = { project: large, tracker: feature, subject: 'S2 show target', values: { assembly => 'A010', part => 'A010-P05' } }
s2_specs[1] = { project: large, tracker: feature, subject: 'S2 update target', values: { assembly => 'A011', part => 'A011-P07' } }
s2_ids = bulk_insert_issues(s2_specs, author: admin, status_pool: [status_new, status_prog], priority: priority)
log "S2: #{s2_ids.size} issues"
base_specs = (1..50).map do |i|
  { project: baseline, tracker: feature, subject: format('Baseline issue %02d', i), values: { plain => pick(plain_values) } }
end
base_ids = bulk_insert_issues(base_specs, author: admin, status_pool: [status_new], priority: priority)

# ----------------------------------------------------------------- ids for the harness
targets = [s1_ids[bug_a[0]], s1_ids[bug_a[1]]]
s1_a_ids = s1_ids.each_index.select { |i| s1_specs[i][:project] == s1_projects[0] }.map { |i| s1_ids[i] } - targets
IDS['issues'] = {
  's1_show' => targets[0], 's1_update' => targets[1], 's2_show' => s2_ids[0], 's2_update' => s2_ids[1],
  's1_ctx_ids' => s1_a_ids.first(10), 's2_ctx_ids' => s2_ids[2, 10], 'baseline_first' => base_ids[0]
}
IDS['values'] = {
  'countries' => countries, 'cities' => cities, 'districts' => districts, 'langs' => langs,
  'zone_ids' => zones.map { |z| z.id.to_s }, 'sites_by_zone' => sites_by_zone,
  's1_show' => fixed['show'], 's1_update' => fixed['update'],
  's2_show' => { 'assembly' => 'A010', 'part' => 'A010-P05' }, 's2_update' => { 'assembly' => 'A011', 'part' => 'A011-P07' },
  's2_new_assembly' => 'A012', 's2_new_part' => 'A012-P09'
}
IDS['counts'] = { 's1_issues' => s1_ids.size, 's2_issues' => s2_ids.size, 'baseline_issues' => base_ids.size }

# ----------------------------------------------------------------- verification through the models
log 'verifying through the models'
errors = []
sample = (s1_ids.sample(40, random: RNG) + s2_ids.sample(40, random: RNG) + base_ids.first(5) + targets +
          [s2_ids[0], s2_ids[1]]).uniq
sample.each do |id|
  issue = Issue.find(id)
  errors << "issue #{id} invalid: #{issue.errors.full_messages.join(', ')}" unless issue.valid?
end
# Full consistency check straight from the stored values: every child value is allowed by the parent value.
[[city, country, cities], [district, city, districts], [languages, country, langs], [part, assembly, part_map]].each do |child, parent, map|
  cvs = CustomValue.where(customized_type: 'Issue', custom_field_id: [child.id, parent.id]).where.not(value: '')
                   .pluck(:customized_id, :custom_field_id, :value).group_by(&:first)
  bad = 0
  cvs.each_value do |rows|
    pv = rows.select { |r| r[1] == parent.id }.map(&:last)
    cv = rows.select { |r| r[1] == child.id }.map(&:last)
    allowed = pv.flat_map { |v| map[v] || [] }
    bad += cv.count { |v| !allowed.include?(v) }
  end
  errors << "#{child.name}: #{bad} stored values not allowed by #{parent.name}" if bad.positive?
end
errors << 'S1 count' unless Issue.where(project_id: s1_projects.map(&:id)).count == 300
errors << 'S2 count' unless Issue.where(project_id: large.id).count == 2000
errors << 'Part values' unless IssueCustomField.find(part.id).possible_values.size == 25_000
errors << 'Plain values' unless IssueCustomField.find(plain.id).possible_values.size == 25_000
errors << 'Part mapping' unless IssueCustomField.find(part.id).value_dependencies.values.sum(&:size) == 25_000
unless errors.empty?
  warn errors.join("\n")
  abort 'verification failed'
end
log "verified: #{sample.size} issues valid, mappings consistent; cache store #{Rails.cache.class}"
File.write(OUT, JSON.pretty_generate(IDS))
log "ids written to #{OUT}"
