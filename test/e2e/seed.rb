# Plugin data for the e2e server, run by .codex/start_server.sh after the
# generic seed (.codex/e2e/seed.rb). Idempotent.
#
#   editor   member of e2e-project with every permission except
#            :manage_project_custom_field_configuration, so Project > Settings
#            opens but the custom field configuration tab must not be there
#   E2E colour (list) and E2E size (key/value list), issue fields for all
#            projects, so the tab has something to show

User.current = User.find_by(login: 'admin')
password = ENV.fetch('RMP_USER_PASSWORD', ENV.fetch('RMP_ADMIN_PASSWORD', 'Redmine7Test!'))

editor = User.find_by(login: 'editor') ||
         User.new(login: 'editor', firstname: 'Editor', lastname: 'E2E', mail: 'editor@example.net')
editor.password = editor.password_confirmation = password
editor.must_change_passwd = false
editor.status = User::STATUS_ACTIVE
editor.save!(validate: false)

role = Role.find_by(name: 'E2E without CF configuration') ||
       Role.new(name: 'E2E without CF configuration', assignable: true)
role.permissions = Redmine::AccessControl.permissions.reject(&:public?).map(&:name) -
                   [:manage_project_custom_field_configuration]
role.save!

project = Project.find_by!(identifier: 'e2e-project')
Member.create!(principal: editor, project: project, roles: [role]) unless
  Member.where(user_id: editor.id, project_id: project.id).exists?

unless IssueCustomField.exists?(name: 'E2E colour')
  IssueCustomField.create!(name: 'E2E colour', field_format: 'list', possible_values: %w[Red Green Blue],
                           is_for_all: true, trackers: Tracker.all)
end
unless IssueCustomField.exists?(name: 'E2E size')
  size = IssueCustomField.create!(name: 'E2E size', field_format: 'enumeration', is_for_all: true,
                                  trackers: Tracker.all)
  %w[Small Medium Large].each_with_index do |n, i|
    CustomFieldEnumeration.create!(custom_field_id: size.id, name: n, position: i + 1, active: true)
  end
end

puts "Plugin seed: editor, role #{role.name}, fields #{IssueCustomField.where(name: ['E2E colour', 'E2E size']).pluck(:name).join(', ')}"
