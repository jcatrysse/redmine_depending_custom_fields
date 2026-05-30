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

  # status: :active (default), :closed (read-only — read:true permissions still
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

  # A bare CustomValue row (no real issue) — enough to test the value rewrite,
  # which is scoped by custom_field_id + value (no project join).
  def dcf_custom_value(field, value, customized_id: 999_999)
    CustomValue.create!(customized_type: 'Issue', customized_id: customized_id,
                        custom_field_id: field.id, value: value.to_s)
  end
end

RSpec.configure do |config|
  config.include DcfConfigHelpers
end
