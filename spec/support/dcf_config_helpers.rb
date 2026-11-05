# Builders for project-level custom field configuration specs. The DB starts
# empty (only the admin user fixture), so these create the records each example
# needs; transactional fixtures roll them back afterwards.
module DcfConfigHelpers
  def dcf_admin
    User.find(1)
  end

  def dcf_create_user(login)
    user = User.new(login: login, firstname: 'F', lastname: login.capitalize, status: User::STATUS_ACTIVE, admin: false)
    user.save!(validate: false)
    user
  end

  # status: :active (default), :closed (read-only: read:true permissions still
  # work), or :archived (Redmine denies all access).
  def dcf_create_project(name: 'Project', active: true, status: nil)
    status ||= active ? :active : :archived
    project = Project.new(name: name, identifier: "dcf-#{SecureRandom.hex(4)}")
    project.status = { active: Project::STATUS_ACTIVE,
                       closed: Project::STATUS_CLOSED,
                       archived: Project::STATUS_ARCHIVED }[status]
    project.save!(validate: false)
    project
  end

  def dcf_create_role(permissions: [])
    Role.create!(name: "Role-#{SecureRandom.hex(4)}", permissions: permissions)
  end

  def dcf_add_member(user, project, role)
    Member.create!(principal: user, project: project, roles: [role])
  end

  # A user that is a member of +project+ holding the management permission.
  def dcf_manager(project)
    role = dcf_create_role(permissions: [:manage_project_custom_field_configuration])
    user = dcf_create_user("mgr-#{SecureRandom.hex(3)}")
    dcf_add_member(user, project, role)
    user
  end

  def dcf_plain_member(project)
    role = dcf_create_role(permissions: [])
    user = dcf_create_user("plain-#{SecureRandom.hex(3)}")
    dcf_add_member(user, project, role)
    user
  end

  def dcf_list_field(format: 'list', values: %w[A B C], is_for_all: true, name: nil,
                     type: IssueCustomField, parent: nil, projects: nil, multiple: false,
                     default_value: nil)
    name ||= "List-#{SecureRandom.hex(4)}"
    cf = type.new(name: name, field_format: format, possible_values: values,
                  is_for_all: is_for_all, multiple: multiple)
    cf.parent_custom_field_id = parent.id if parent
    cf.default_value = default_value if default_value
    cf.save!
    cf.projects = projects if projects
    cf.reload
  end

  def dcf_enum_field(format: 'enumeration', names: %w[X Y Z], is_for_all: true, name: nil,
                     type: IssueCustomField, parent: nil)
    name ||= "Enum-#{SecureRandom.hex(4)}"
    cf = type.new(name: name, field_format: format, is_for_all: is_for_all)
    cf.parent_custom_field_id = parent.id if parent
    cf.save!
    names.each_with_index do |n, i|
      CustomFieldEnumeration.create!(custom_field_id: cf.id, name: n, position: i + 1, active: true)
    end
    cf.reload
  end

  def dcf_set_dependencies(field, value_dependencies: {}, default_value_dependencies: {})
    field.update!(value_dependencies: value_dependencies,
                  default_value_dependencies: default_value_dependencies)
    field.reload
  end

  # Minimal issue infrastructure for usage-count specs.
  def dcf_issue_infra(project)
    status = IssueStatus.first || IssueStatus.create!(name: 'New', is_closed: false)
    priority = IssuePriority.first || IssuePriority.create!(name: 'Normal')
    tracker = Tracker.first
    unless tracker
      tracker = Tracker.new(name: 'Bug')
      tracker.default_status = status
      tracker.save!
    end
    project.trackers << tracker unless project.trackers.include?(tracker)
    [tracker, status, priority]
  end

  def dcf_issue_with_value(project, field, value)
    tracker, status, priority = dcf_issue_infra(project)
    issue = Issue.new(project: project, tracker: tracker, subject: 'S',
                      author: dcf_admin, status: status, priority: priority)
    issue.save!(validate: false)
    CustomValue.create!(customized_type: 'Issue', customized_id: issue.id,
                        custom_field_id: field.id, value: value.to_s)
    issue
  end

  # An issue whose custom field values go through Redmine's real validation,
  # unlike dcf_issue_with_value / dcf_custom_value which write the CustomValue
  # row directly. +values+ maps CustomField => value; each field must be linked
  # to the tracker or Issue#available_custom_fields ignores it and nothing is
  # stored.
  def dcf_real_issue(project, values)
    tracker, status, priority = dcf_issue_infra(project)
    values.each_key { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
    tracker.save!
    issue = Issue.new(project: project, tracker: tracker, subject: 'S',
                      author: dcf_admin, status: status, priority: priority)
    issue.custom_field_values = values.transform_keys(&:id)
    issue.save!
    issue
  end

  # A bare CustomValue row (no real issue): enough to test the value rewrite,
  # which is scoped by custom_field_id + value (no project join).
  def dcf_custom_value(field, value, customized_id: 999_999)
    CustomValue.create!(customized_type: 'Issue', customized_id: customized_id,
                        custom_field_id: field.id, value: value.to_s)
  end

  # Fixed, disjoint id ranges for records whose ids end up in rendered markup
  # or JSON fixtures, so the output is the same on every run and version.
  DCF_FIXTURE_ID_BASES = {
    'CustomField' => 9_100_001,
    'CustomFieldEnumeration' => 9_200_001,
    'Issue' => 9_300_001,
    'Project' => 9_400_001,
    'User' => 9_500_001,
    'Role' => 9_600_001,
    'Tracker' => 9_700_001,
    'IssueStatus' => 9_800_001
  }.freeze

  # Builds and saves +klass+ with the next id of its range. Pass the attributes
  # as an explicit Hash (braces): validate: is a keyword. Pass a block to set
  # attributes that are not mass-assignable. validate: false mirrors the
  # existing builders for records whose validations need unrelated setup.
  # WP-16: a class without a range of its own uses its base class range, so
  # User (base class Principal) gets the User range.
  def dcf_fixture_record(klass, attributes = {}, validate: true)
    base_name = DCF_FIXTURE_ID_BASES.key?(klass.name) ? klass.name : klass.base_class.name
    base = DCF_FIXTURE_ID_BASES.fetch(base_name) { raise ArgumentError, "no fixture id range for #{base_name}" }
    @dcf_fixture_counters ||= Hash.new(0)
    record = klass.new
    attributes.each { |name, value| record.send("#{name}=", value) }
    yield record if block_given?
    record.id = base + @dcf_fixture_counters[base_name]
    @dcf_fixture_counters[base_name] += 1
    record.save!(validate: validate)
    record
  end

  def dcf_issue_status(name: "Status-#{SecureRandom.hex(3)}", is_closed: false)
    IssueStatus.create!(name: name, is_closed: is_closed)
  end

  # A tracker with its own default status (Redmine requires one).
  def dcf_tracker(name: "Tracker-#{SecureRandom.hex(3)}", default_status: nil)
    tracker = Tracker.new(name: name)
    tracker.default_status = default_status || dcf_issue_status
    tracker.save!
    tracker
  end

  # WP-36: the request headers of context_menu_wizard.js for the wizard body.
  DCF_WIZARD_HEADERS = { 'X-Requested-With' => 'XMLHttpRequest', 'Accept' => 'text/html' }.freeze

  # WP-36: GET of the wizard body as the script asks for it (parent_id and
  # ids[] from the entry), in a request spec. Returns the response.
  def dcf_get_wizard(parent_id, ids, env: {}, headers: DCF_WIZARD_HEADERS)
    get '/depending_custom_fields/wizard', params: { parent_id: parent_id.to_s, ids: Array(ids).map(&:to_s) },
                                           headers: headers, env: env
    response
  end

  # WP-36: the wizard form the script fetches for the entry of +root+ (a
  # field or its id) in the parsed context menu +menu+, or nil when the menu
  # has no entry for it or the body is not a 200 with one form. The ids are
  # the entry's.
  def dcf_wizard_form(menu, root, env: {})
    root_id = root.respond_to?(:id) ? root.id : root
    entry = menu.at_css("li.folder.cf-parent[data-parent-id='#{root_id}']")
    return nil unless entry

    dcf_get_wizard(root_id, entry['data-issue-ids'].to_s.split(','), env: env)
    return nil unless response.status == 200

    forms = Nokogiri::HTML(response.body).css('form.cf-wizard-form')
    forms.size == 1 ? forms.first : nil
  end

  # WP-39 (R1): the mapping of a managed control is the JSON text of a
  # <script type="application/json"> element whose data-dcf-map-id the
  # control names in data-dcf-map-ref (was the data-dcf-map attribute).
  DCF_MAP_REF = 'data-dcf-map-ref'
  DCF_MAP_SCRIPT = 'script[type="application/json"]'

  # The JSON script elements of a parsed page or fragment.
  def dcf_map_scripts(page)
    page.css(DCF_MAP_SCRIPT)
  end

  # The controls that name a mapping script.
  def dcf_mapped(page)
    page.css("[#{DCF_MAP_REF}]")
  end

  # The one JSON script of the control's document (or fragment) whose data-dcf-map-id is the control's
  # reference (nil without a reference; fails unless exactly one matches).
  def dcf_map_script(control)
    ref = control[DCF_MAP_REF]
    return nil if ref.nil?

    root = control.ancestors.last || control # the document, or the fragment of a tag
    found = dcf_map_scripts(root).select { |script| script['data-dcf-map-id'] == ref }
    expect(found.size).to eq(1), "#{found.size} mapping scripts for #{ref.inspect}"

    found.first
  end

  # The number of managed controls of a parsed page: as many JSON scripts as
  # controls with a reference, each reference resolving to one of them.
  def dcf_managed_count(page)
    controls = dcf_mapped(page)
    expect(dcf_map_scripts(page).size).to eq(controls.size)
    expect(controls.map { |control| dcf_map_script(control) }.uniq.size).to eq(controls.size)
    controls.size
  end

  # The parsed mapping of the control, nil when it names none.
  def dcf_map_of(control)
    script = dcf_map_script(control)
    script && JSON.parse(script.text)
  end

  # A raw body (page, fragment or edit.js) without any mapping markup:
  # neither the former attribute nor the reference (data-dcf-map is its
  # prefix) nor a JSON script element.
  def dcf_expect_no_map_markup(body, label = nil)
    expect(body).not_to include('data-dcf-map'), label
    expect(body).not_to match(%r{<script[^>]*application/json}), label
  end
end

RSpec.configure do |config|
  config.include DcfConfigHelpers
end
