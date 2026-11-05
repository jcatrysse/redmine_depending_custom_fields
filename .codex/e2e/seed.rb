# frozen_string_literal: true

# Idempotent walkthrough seed for redmine_depending_custom_fields.
# Run: cd <checkout> && RAILS_ENV=development bundle exec rails runner <this file>
# Works on Redmine 5.1 and 7.0. Writes ids to $E2E_DIR/out/ids-<database>.json.
require 'json'
require 'fileutils'

E2E = ENV['E2E_DIR'] || File.join(ENV.fetch('DCF_WORK_DIR'), 'e2e')
ActionMailer::Base.perform_deliveries = false
t0 = Time.now
def log(msg)
  puts("[seed] #{msg}")
end

DB = begin
  ActiveRecord::Base.connection_db_config.database
rescue StandardError
  ActiveRecord::Base.connection.current_database
end
IDS = { 'database' => DB, 'redmine' => Redmine::VERSION.to_s, 'fields' => {}, 'projects' => {}, 'users' => {},
        'roles' => {}, 'trackers' => {}, 'urls' => {} }

PASSWORD = 'Passw0rd!x'
ADMIN_PASSWORD = 'admin123!'

# ---------------------------------------------------------------- settings
Setting.rest_api_enabled = '1'
Setting.default_language = 'en'
Setting.plugin_redmine_depending_custom_fields = (Setting.plugin_redmine_depending_custom_fields || {}).merge(
  'manage_standard_custom_fields' => '1', 'block_removal_when_used' => '0', 'project_storage_ceiling_kib' => '2048'
)

# ------------------------------------------------------------------- roles
manager_role = Role.find_by!(name: 'Manager')
developer_role = Role.find_by!(name: 'Developer')
reporter_role = Role.find_by!(name: 'Reporter')
manager_role.add_permission!(:manage_project_custom_field_configuration)
manager_role.add_permission!(:log_time)
developer_role.add_permission!(:log_time)
reporter_role.add_permission!(:log_time)
IDS['roles'] = { 'Manager' => manager_role.id, 'Developer' => developer_role.id, 'Reporter' => reporter_role.id }

# ------------------------------------------------------------------- users
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
manager = upsert_user('manager', 'Mia', 'Manager', PASSWORD)
developer = upsert_user('developer', 'Dev', 'Developer', PASSWORD)
reporter = upsert_user('reporter', 'Rita', 'Reporter', PASSWORD)
IDS['users'] = { 'admin' => admin.id, 'manager' => manager.id, 'developer' => developer.id, 'reporter' => reporter.id }
User.current = admin

# ---------------------------------------------------------------- trackers
bug = Tracker.find_by!(name: 'Bug')
feature = Tracker.find_by!(name: 'Feature')
IDS['trackers'] = { 'Bug' => bug.id, 'Feature' => feature.id }

# ---------------------------------------------------------------- projects
def upsert_project(name, identifier, trackers:, parent: nil)
  p = Project.find_by(identifier: identifier) || Project.new(identifier: identifier)
  p.name = name
  p.is_public = false
  p.parent = parent if parent
  p.enabled_module_names = %w[issue_tracking time_tracking]
  p.trackers = trackers
  p.save!
  p
end
walk = upsert_project('Walk', 'walk', trackers: [bug, feature])
walk_sub = upsert_project('Walk Sub', 'walk-sub', parent: walk, trackers: [bug, feature])
other = upsert_project('Other', 'other', trackers: [bug, feature])
IDS['projects'] = { 'Walk' => { 'id' => walk.id, 'identifier' => 'walk' },
                    'Walk Sub' => { 'id' => walk_sub.id, 'identifier' => 'walk-sub' },
                    'Other' => { 'id' => other.id, 'identifier' => 'other' } }

def ensure_member(user, project, role)
  m = Member.find_by(user_id: user.id, project_id: project.id) || Member.new(principal: user, project: project)
  m.roles = [role]
  m.save!
end
[walk, walk_sub, other].each do |pr|
  ensure_member(manager, pr, manager_role)
  ensure_member(developer, pr, developer_role)
end
[walk, walk_sub].each { |pr| ensure_member(reporter, pr, reporter_role) }

# ------------------------------------------------------------ field helpers
# kind: IssueCustomField, TimeEntryCustomField, ProjectCustomField
def upsert_field(klass, name, format, was: nil, values: nil, parent: nil, multiple: false, required: false,
                 all: false, projects: [], trackers: [], roles: nil, hide_when_disabled: false,
                 mapping: nil, defaults: nil, searchable: false)
  cf = klass.find_by(name: name) || (was && klass.find_by(name: was)) || klass.new(name: name)
  cf.name = name
  cf.field_format = format
  cf.multiple = multiple
  cf.is_required = required
  cf.visible = roles.nil?
  cf.role_ids = roles if roles
  cf.possible_values = values if values
  cf.parent_custom_field_id = parent.id if parent
  cf.hide_when_disabled = hide_when_disabled ? '1' : '0' if %w[depending_list depending_enumeration].include?(format)
  cf.value_dependencies = mapping if mapping
  cf.default_value_dependencies = defaults if defaults
  if klass == IssueCustomField
    cf.is_for_all = all
    cf.is_filter = true
    cf.tracker_ids = trackers.map(&:id)
    cf.project_ids = projects.map(&:id) unless all
  end
  cf.save!
  cf
end

def add_enums(cf, names)
  names.each_with_index.to_h do |n, i|
    e = CustomFieldEnumeration.find_by(custom_field_id: cf.id, name: n) ||
        CustomFieldEnumeration.create!(custom_field_id: cf.id, name: n, position: i + 1, active: true)
    [n, e.id.to_s]
  end
end

def record(name, cf)
  IDS['fields'][name] = { 'id' => cf.id, 'format' => cf.field_format, 'type' => cf.class.name,
                          'parent_id' => cf.parent_custom_field_id, 'multiple' => cf.multiple?,
                          'required' => cf.is_required?, 'is_for_all' => (cf.respond_to?(:is_for_all?) ? cf.is_for_all? : nil),
                          'visible' => cf.visible?, 'role_ids' => cf.role_ids }
end

both = [bug, feature]
common = { trackers: both, all: true }

# ------------------------------------------------------------------ Country
countries = %w[Belgium Netherlands France Germany]
country = upsert_field(IssueCustomField, 'Country', 'list', values: countries, **common)
record('Country', country)

city_map = { 'Belgium' => %w[Brussels Ghent Antwerp], 'Netherlands' => %w[Amsterdam Utrecht],
             'France' => %w[Paris Lyon], 'Germany' => [] }
city = upsert_field(IssueCustomField, 'City', 'depending_list', values: city_map.values.flatten, parent: country,
                    mapping: city_map.reject { |_, v| v.empty? },
                    defaults: { 'Belgium' => 'Brussels', 'Netherlands' => 'Amsterdam' }, **common)
record('City', city)

district_map = { 'Brussels' => ['Ixelles', 'Schaerbeek', 'Uccle'], 'Ghent' => ['Gentbrugge', 'Mariakerke'],
                 'Antwerp' => ['Berchem', 'Borgerhout'], 'Amsterdam' => ['Centrum', 'Zuid', 'Noord'],
                 'Utrecht' => ['Leidsche Rijn', 'Overvecht'], 'Paris' => ['Le Marais', 'Montmartre'],
                 'Lyon' => ['Croix-Rousse'] }
district = upsert_field(IssueCustomField, 'District', 'depending_list', values: district_map.values.flatten.uniq,
                        parent: city, mapping: district_map, defaults: { 'Brussels' => 'Ixelles' }, **common)
record('District', district)

lang_map = { 'Belgium' => %w[Dutch French German], 'Netherlands' => %w[Dutch Frisian], 'France' => %w[French],
             'Germany' => %w[German] }
languages = upsert_field(IssueCustomField, 'Languages', 'depending_list', values: lang_map.values.flatten.uniq,
                         parent: country, multiple: true, mapping: lang_map,
                         defaults: { 'Belgium' => %w[Dutch French] }, **common)
record('Languages', languages)

zone_map = { 'Belgium' => %w[B-1000 B-9000 B-2000], 'Netherlands' => %w[NL-1011 NL-3511], 'France' => %w[F-75001] }
postal = upsert_field(IssueCustomField, 'Postal Zone', 'depending_list', values: zone_map.values.flatten, parent: country,
                      required: true, mapping: zone_map, defaults: { 'Belgium' => 'B-1000' }, **common)
record('Postal Zone', postal)

# Depending list that hides itself while the parent allows nothing.
hidden_when_empty = upsert_field(IssueCustomField, 'Landmark', 'depending_list',
                                 values: %w[Atomium Manneken-Pis Eiffel-Tower Windmill], parent: country,
                                 hide_when_disabled: true,
                                 mapping: { 'Belgium' => %w[Atomium Manneken-Pis], 'France' => %w[Eiffel-Tower],
                                            'Netherlands' => %w[Windmill] }, **common)
record('Landmark', hidden_when_empty)

# ------------------------------------------------------ enumeration pair
zone = upsert_field(IssueCustomField, 'Zone', 'enumeration', **common)
zone_ids = add_enums(zone, %w[North South East])
record('Zone', zone)
site = upsert_field(IssueCustomField, 'Site', 'depending_enumeration', parent: zone, **common)
site_ids = add_enums(site, ['North Dock', 'North Yard', 'South Dock', 'South Yard', 'East Gate'])
site.value_dependencies = { zone_ids['North'] => [site_ids['North Dock'], site_ids['North Yard']],
                            zone_ids['South'] => [site_ids['South Dock'], site_ids['South Yard']] }
site.default_value_dependencies = { zone_ids['North'] => site_ids['North Dock'] }
site.save!
record('Site', site)
IDS['enumerations'] = { 'Zone' => zone_ids, 'Site' => site_ids }

# --------------------------------------------- role-restricted (hidden) field
secret_map = { 'Belgium' => %w[Zulu-7731 Zulu-7732], 'Netherlands' => %w[Yankee-4410], 'France' => %w[Xray-9981],
               'Germany' => %w[Whiskey-2208] }
secret = upsert_field(IssueCustomField, 'Secret Code', 'depending_list', values: secret_map.values.flatten, parent: country,
                      roles: [manager_role.id], mapping: secret_map, defaults: { 'Belgium' => 'Zulu-7731' }, **common)
record('Secret Code', secret)

# Hidden PARENT with a visible child (the page of a user without the role must
# hold neither the parent nor its mapping).
clearance = upsert_field(IssueCustomField, 'Clearance', 'list', values: %w[Alpha-Level Bravo-Level],
                         roles: [manager_role.id], **common)
record('Clearance', clearance)
area = upsert_field(IssueCustomField, 'Access Area', 'depending_list', was: 'Clearance Area', values: ['Area-51', 'Area-52', 'Area-61'],
                    parent: clearance, mapping: { 'Alpha-Level' => %w[Area-51 Area-52], 'Bravo-Level' => %w[Area-61] },
                    **common)
record('Access Area', area)

# ------------------------------------------- project-scoped and shared pairs
# Scope on the project pages: Country, City and the other is_for_all fields are
# global; 'Walk Local *' is enabled in Walk only (project); 'Shared *' is
# enabled in Walk and Other (shared).
local_parent = upsert_field(IssueCustomField, 'Walk Local Parent', 'list', values: %w[Alpha Beta Gamma], projects: [walk],
                            trackers: both)
record('Walk Local Parent', local_parent)
local_child = upsert_field(IssueCustomField, 'Walk Local Child', 'depending_list', values: %w[A1 A2 B1 B2 B3],
                           parent: local_parent, projects: [walk], trackers: both,
                           mapping: { 'Alpha' => %w[A1 A2], 'Beta' => %w[B1 B2 B3] }, defaults: { 'Alpha' => 'A1' })
record('Walk Local Child', local_child)
shared_parent = upsert_field(IssueCustomField, 'Shared Parent', 'list', values: %w[Red Green], projects: [walk, other],
                             trackers: both)
record('Shared Parent', shared_parent)
shared_child = upsert_field(IssueCustomField, 'Shared Child', 'depending_list', values: %w[Rose Ruby Lime Moss],
                            parent: shared_parent, projects: [walk, other], trackers: both,
                            mapping: { 'Red' => %w[Rose Ruby], 'Green' => %w[Lime Moss] }, defaults: { 'Red' => 'Rose' })
record('Shared Child', shared_child)

# Project-level standard (non depending) fields, to cover the plain pages.
plain_list = upsert_field(IssueCustomField, 'Walk Plain List', 'list', values: %w[One Two Three], projects: [walk], trackers: both)
record('Walk Plain List', plain_list)

# ------------------------------------------------------- large depending list
assembly_keys = (1..500).map { |i| format('A%03d', i) }
part_map = {}
part_values = []
assembly_keys.each do |a|
  parts = (1..50).map { |k| format('%s-P%02d', a, k) }
  part_map[a] = parts
  part_values.concat(parts)
end
assembly = upsert_field(IssueCustomField, 'Assembly', 'list', values: assembly_keys, projects: [walk], trackers: [feature])
record('Assembly', assembly)
part_defaults = assembly_keys.to_h { |a| [a, part_map[a].first] }
t1 = Time.now
if IssueCustomField.find_by(name: 'Part')&.possible_values&.size == part_values.size
  part = IssueCustomField.find_by(name: 'Part')
  part.update!(parent_custom_field_id: assembly.id, value_dependencies: part_map, default_value_dependencies: part_defaults) if part.value_dependencies.blank?
else
  part = upsert_field(IssueCustomField, 'Part', 'depending_list', values: part_values, parent: assembly,
                      projects: [walk], trackers: [feature], mapping: part_map, defaults: part_defaults)
end
log "Part saved with #{part.possible_values.size} values over #{part.value_dependencies.size} parents in #{(Time.now - t1).round(1)}s"
record('Part', part)

# -------------------------------------------------- time entry field pair
te_kind = upsert_field(TimeEntryCustomField, 'Work Kind', 'list', values: %w[Development Operations Support])
record('Work Kind', te_kind)
te_detail = upsert_field(TimeEntryCustomField, 'Work Detail', 'depending_list',
                         values: %w[Coding Review Testing Deploy Monitor Triage], parent: te_kind,
                         mapping: { 'Development' => %w[Coding Review Testing], 'Operations' => %w[Deploy Monitor],
                                    'Support' => %w[Triage] },
                         defaults: { 'Development' => 'Coding' })
record('Work Detail', te_detail)

# ------------------------------------------------------ project custom fields
pc_parent = upsert_field(ProjectCustomField, 'Program Area', 'list', values: %w[Alpha Beta])
record('Program Area', pc_parent)
pc_child = upsert_field(ProjectCustomField, 'Program Team', 'depending_list', values: %w[Red Blue Green],
                        parent: pc_parent, mapping: { 'Alpha' => %w[Red Blue], 'Beta' => %w[Green] })
record('Program Team', pc_child)

# ------------------------------------------------------------------ issues
priority = IssuePriority.find_by(is_default: true) || IssuePriority.first
statuses = IssueStatus.where(name: ['New', 'In Progress', 'Resolved']).to_a
def cf_id(cf)
  cf.id
end

def make_issue(subject, project:, tracker:, author:, status:, priority:, assignee: nil, values: {})
  issue = Issue.find_by(subject: subject, project_id: project.id)
  return issue if issue

  issue = Issue.new(project: project, tracker: tracker, subject: subject, author: author, status: status,
                    priority: priority, assigned_to: assignee, description: "Seeded issue #{subject}")
  issue.custom_field_values = values.transform_keys(&:id)
  unless issue.save
    raise "issue '#{subject}' invalid: #{issue.errors.full_messages.join('; ')}"
  end

  issue
end

cycle = [
  ['Belgium', 'Brussels', 'Ixelles', %w[Dutch French], 'B-1000', 'Zulu-7731', 'North', 'North Dock'],
  ['Belgium', 'Ghent', 'Mariakerke', %w[Dutch], 'B-9000', nil, 'South', 'South Dock'],
  ['Belgium', 'Antwerp', nil, %w[Dutch French German], 'B-2000', 'Zulu-7732', nil, nil],
  ['Netherlands', 'Amsterdam', 'Zuid', %w[Dutch], 'NL-1011', 'Yankee-4410', 'North', 'North Yard'],
  ['Netherlands', 'Utrecht', 'Overvecht', %w[Dutch Frisian], 'NL-3511', nil, 'South', nil],
  ['France', 'Paris', 'Montmartre', %w[French], 'F-75001', 'Xray-9981', 'East', nil],
  ['France', 'Lyon', 'Croix-Rousse', %w[French], 'F-75001', nil, nil, nil],
  ['Germany', nil, nil, %w[German], nil, 'Whiskey-2208', nil, nil],
  [nil, nil, nil, [], nil, nil, nil, nil]
]
author_pool = [admin, manager, developer, reporter]
issue_count = 0
(1..30).each do |n|
  c = cycle[(n - 1) % cycle.size]
  tracker = n.even? ? feature : bug
  project = (n % 10).zero? ? walk_sub : walk
  vals = { country => c[0], city => c[1], district => c[2], languages => c[3], postal => c[4], secret => c[5],
           zone => zone_ids[c[6]], site => site_ids[c[7]] }
  vals[secret] = nil if n % 3 == 1 # some issues leave the hidden field empty
  vals[hidden_when_empty] = { 'Belgium' => 'Atomium', 'France' => 'Eiffel-Tower' }[c[0]]
  if tracker == feature
    a = assembly_keys[(n * 37) % 500]
    vals[assembly] = a
    vals[part] = part_map[a][n % 50]
  end
  if project == walk
    vals[local_parent] = n.odd? ? 'Alpha' : 'Beta'
    vals[local_child] = n.odd? ? 'A1' : 'B2'
    vals[shared_parent] = n % 3 == 0 ? 'Red' : 'Green'
    vals[shared_child] = n % 3 == 0 ? 'Rose' : 'Lime'
  end
  vals[clearance] = n % 4 == 0 ? 'Alpha-Level' : nil
  vals[area] = n % 4 == 0 ? 'Area-51' : nil
  make_issue(format('Seed issue %02d', n), project: project, tracker: tracker, author: author_pool[n % 4],
             status: statuses[n % 3], priority: priority, assignee: (n % 2).zero? ? developer : nil, values: vals)
  issue_count += 1
end

# Stored values that the parent no longer allows (legacy data): City Paris under Belgium.
legacy = []
[['Seed legacy mismatch 1', bug], ['Seed legacy mismatch 2', feature]].each_with_index do |(subj, trk), i|
  vals = { country => 'Belgium', city => 'Brussels', postal => 'B-1000', secret => 'Zulu-7731' }
  issue = make_issue(subj, project: walk, tracker: trk, author: manager, status: statuses[0], priority: priority, values: vals)
  cv = CustomValue.find_by(customized_type: 'Issue', customized_id: issue.id, custom_field_id: city.id)
  cv.update_column(:value, i.zero? ? 'Paris' : 'Amsterdam')
  legacy << issue.id
end
# An issue in Other (shared fields enabled there) and a few time entries.
make_issue('Seed other issue', project: other, tracker: bug, author: manager, status: statuses[0], priority: priority,
           values: { country => 'France', city => 'Lyon', postal => 'F-75001', shared_parent => 'Red', shared_child => 'Ruby' })

activity = TimeEntryActivity.find_by(name: 'Development') || TimeEntryActivity.first
first_issue = Issue.find_by(subject: 'Seed issue 01', project_id: walk.id)
[['Development', 'Coding'], ['Operations', 'Deploy'], ['Support', 'Triage']].each_with_index do |(k, d), i|
  comments = "Seed time entry #{i + 1}"
  next if TimeEntry.exists?(comments: comments)

  te = TimeEntry.new(project: walk, issue: first_issue, user: developer, author: developer, hours: 1 + i, spent_on: Date.today,
                     activity: activity, comments: comments)
  te.custom_field_values = { te_kind.id => k, te_detail.id => d }
  te.save!
end

# -------------------------------------------- project-level configuration audit
begin
  if RedmineDependingCustomFields::ConfigAuditEvent.where(project_id: walk.id).none?
    User.current = manager
    RedmineDependingCustomFields::SetDefaultValueService.new(project: walk, field: plain_list, user: manager,
                                                             params: { default_value: 'Two' }).call
    RedmineDependingCustomFields::SetDefaultValueService.new(project: walk, field: local_parent, user: manager,
                                                             params: { default_value: 'Gamma' }).call
    User.current = admin
  end
rescue StandardError => e
  log "audit seed skipped: #{e.class}: #{e.message}"
  User.current = admin
end

IDS['urls'] = {
  'login' => '/login',
  'new_issue_walk' => '/projects/walk/issues/new',
  'new_issue_walk_feature' => "/projects/walk/issues/new?issue[tracker_id]=#{feature.id}",
  'issues_walk' => '/projects/walk/issues',
  'project_settings_cfc' => '/projects/walk/settings/custom_field_configuration',
  'cfc_index' => '/projects/walk/custom_field_configuration',
  'cfc_audit' => '/projects/walk/custom_field_configuration/audit',
  'cfc_values_city' => "/projects/walk/custom_field_configuration/fields/#{city.id}",
  'cfc_deps_city' => "/projects/walk/custom_field_configuration/fields/#{city.id}/dependencies",
  'cfc_values_part' => "/projects/walk/custom_field_configuration/fields/#{part.id}",
  'cfc_deps_part' => "/projects/walk/custom_field_configuration/fields/#{part.id}/dependencies",
  'cfc_values_local_child' => "/projects/walk/custom_field_configuration/fields/#{local_child.id}",
  'cfc_deps_local_child' => "/projects/walk/custom_field_configuration/fields/#{local_child.id}/dependencies",
  'cfc_values_shared_child' => "/projects/walk/custom_field_configuration/fields/#{shared_child.id}",
  'cfc_deps_shared_child' => "/projects/walk/custom_field_configuration/fields/#{shared_child.id}/dependencies",
  'admin_custom_fields' => '/custom_fields',
  'admin_edit_city' => "/custom_fields/#{city.id}/edit",
  'admin_edit_part' => "/custom_fields/#{part.id}/edit",
  'admin_audit' => '/dcf_config_audit',
  'time_entry_new_walk' => '/projects/walk/time_entries/new'
}
IDS['legacy_mismatch_issue_ids'] = legacy
IDS['issue_ids'] = Issue.where('subject LIKE ?', 'Seed%').order(:id).pluck(:id)

FileUtils.mkdir_p(File.join(E2E, 'out'))
File.write(File.join(E2E, 'out', "ids-#{DB}.json"), JSON.pretty_generate(IDS))
log "done in #{(Time.now - t0).round(1)}s; #{Issue.count} issues, #{CustomField.count} custom fields (db #{DB})"
