# Generic data for end-to-end checks, run by start_server.sh through
# `rails runner`. Idempotent: running it again changes nothing.
#
# Users (password RMP_USER_PASSWORD, admin RMP_ADMIN_PASSWORD):
#   admin     administrator
#   manager   role "E2E full" (every permission, the plugin's included) in both projects
#   reporter  core role "Reporter" in e2e-project, so without the plugin's permissions
#   outsider  no membership at all
# Projects: e2e-project (public, every module), e2e-private (private).
# Issues with and without assignee, a closed one, a subtask, a relation, a note,
# an attachment; a version, a wiki page with a child, a time entry.

admin_password = ENV.fetch('RMP_ADMIN_PASSWORD', 'Redmine7Test!')
user_password = ENV.fetch('RMP_USER_PASSWORD', admin_password)

def e2e_user(login, firstname, password, admin: false)
  user = User.find_by(login: login) ||
         User.new(login: login, firstname: firstname, lastname: 'E2E', mail: "#{login}@example.net")
  user.admin = admin
  user.password = user.password_confirmation = password
  user.must_change_passwd = false
  user.status = User::STATUS_ACTIVE
  user.save!(validate: false)
  user
end

admin = e2e_user('admin', 'Redmine', admin_password, admin: true)
User.current = admin
manager = e2e_user('manager', 'Manager', user_password)
reporter = e2e_user('reporter', 'Reporter', user_password)
e2e_user('outsider', 'Outsider', user_password)

full = Role.find_by(name: 'E2E full') || Role.new(name: 'E2E full', assignable: true)
full.permissions = Redmine::AccessControl.permissions.reject(&:public?).map(&:name)
full.issues_visibility = 'all'
full.save!
limited = Role.find_by(name: 'Reporter') || Role.givable.where.not(id: full.id).first

modules = Redmine::AccessControl.available_project_modules.map(&:to_s)

def e2e_project(identifier, name, is_public, modules)
  project = Project.find_by(identifier: identifier) ||
            Project.new(identifier: identifier, name: name, description: "#{name}, for end-to-end checks.")
  project.is_public = is_public
  project.enabled_module_names = modules
  project.trackers = Tracker.all
  project.save!
  project
end

project = e2e_project('e2e-project', 'E2E project', true, modules)
private_project = e2e_project('e2e-private', 'E2E private', false, modules)

[[manager, project, full], [manager, private_project, full], [reporter, project, limited]].each do |user, prj, role|
  next if Member.where(user_id: user.id, project_id: prj.id).exists?

  Member.create!(principal: user, project: prj, roles: [role])
end

version = Version.find_by(project_id: project.id, name: 'E2E 1.0') ||
          Version.create!(project: project, name: 'E2E 1.0', effective_date: Date.today + 30)

def e2e_issue(project, subject, attrs = {})
  issue = Issue.find_by(project_id: project.id, subject: subject)
  return issue if issue

  tracker = attrs.delete(:tracker) || project.trackers.first
  issue = Issue.new(project: project, tracker: tracker, subject: subject, author: User.current,
                    priority: IssuePriority.default || IssuePriority.first,
                    description: "#{subject}.\n\nSecond paragraph with *emphasis* and a list:\n\n* one\n* two")
  issue.status = tracker.default_status
  attrs.each { |k, v| issue.send("#{k}=", v) }
  issue.save!
  # plugins may update the issue in their own callbacks (lock_version)
  issue.reload
end

trackers = project.trackers.to_a
open1 = e2e_issue(project, 'E2E assigned issue', assigned_to: manager, fixed_version: version,
                                                 start_date: Date.today, due_date: Date.today + 7,
                                                 estimated_hours: 4)
e2e_issue(project, 'E2E unassigned issue', tracker: trackers[1] || trackers.first)
child = e2e_issue(project, 'E2E subtask', parent_issue_id: open1.id, assigned_to: reporter)
related = e2e_issue(project, 'E2E related issue', tracker: trackers[2] || trackers.first)
closed_status = IssueStatus.where(is_closed: true).first
closed = e2e_issue(project, 'E2E closed issue')
if closed_status && !closed.closed?
  closed.status = closed_status
  closed.save!
end
e2e_issue(private_project, 'E2E private issue', assigned_to: manager)

unless IssueRelation.where(issue_from_id: open1.id, issue_to_id: related.id).exists?
  IssueRelation.create!(issue_from: open1, issue_to: related, relation_type: 'relates')
end

open1.reload # the subtask recalculated its parent
if open1.journals.where.not(notes: [nil, '']).none?
  open1.init_journal(manager, 'A note from the manager.')
  open1.save!
end

if open1.attachments.none?
  attachment = Attachment.new(file: StringIO.new("E2E attachment\n"), author: admin)
  attachment.filename = 'e2e.txt'
  attachment.content_type = 'text/plain'
  attachment.container = open1
  attachment.save!
end

if project.wiki
  wiki = project.wiki
  start = wiki.find_page(wiki.start_page) || WikiPage.new(wiki: wiki, title: wiki.start_page)
  if start.new_record?
    start.save_with_content(WikiContent.new(text: "Wiki start page. See [[Child page]] and issue ##{open1.id}.",
                                            author: admin))
  end
  unless wiki.find_page('Child page')
    page = WikiPage.new(wiki: wiki, title: 'Child_page', parent: start)
    page.save_with_content(WikiContent.new(text: 'Child page text.', author: admin))
  end
end

if project.module_enabled?(:time_tracking) && TimeEntry.where(issue_id: child.id).none? &&
   (activity = TimeEntryActivity.default || TimeEntryActivity.first)
  TimeEntry.create!(project: project, issue: child, user: manager, author: manager, hours: 1.5,
                    spent_on: Date.today, activity: activity, comments: 'E2E time')
end

Setting.rest_api_enabled = '1'
Setting.host_name = "127.0.0.1:#{ENV.fetch('RMP_PORT', '3000')}"

puts "Seeded: #{User.where(login: %w[admin manager reporter outsider]).count} users, " \
     "#{Issue.where(project_id: [project.id, private_project.id]).count} issues, " \
     "modules: #{modules.join(' ')}"
