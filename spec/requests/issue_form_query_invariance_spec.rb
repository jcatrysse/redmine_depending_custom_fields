# frozen_string_literal: true

require_relative '../rails_helper'

# G6 (WP-06): the issue edit and update requests run the same number of
# queries for 1 depending child of 1 parent and for 5 children of 5 distinct
# parents, all available on the issue. The parent value is read from the
# issue's loaded custom field values, so no per-parent lookup is added.
#
# Each world has its own tracker and project, so an issue only carries the
# fields of its own world, and both worlds exist while either is measured.
# Child values are blank or allowed (since WP-08 a stored inactive, foreign
# or unknown enumeration id makes the edit options look that id up, for any
# depending enumeration child, managed or not).
RSpec.describe 'Issue form query invariance', type: :request do
  fixtures :users

  let(:role) { dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues]) }
  let(:member) { dcf_create_user("inv-#{SecureRandom.hex(3)}") }

  before { allow(User).to receive(:current).and_return(member) }

  def field_key(field, name)
    return name if field.field_format.end_with?('list')

    field.enumerations.detect { |e| e.name == name }.id.to_s
  end

  def new_field(family, depending: false, parent: nil)
    if family == :list
      dcf_list_field(format: depending ? 'depending_list' : 'list', values: depending ? %w[a1 b1] : %w[A B],
                     parent: parent)
    else
      dcf_enum_field(format: depending ? 'depending_enumeration' : 'enumeration',
                     names: depending ? %w[a1 b1] : %w[A B], parent: parent)
    end
  end

  # +total+ parents with value A and +total+ children; the first +managed+
  # children depend on their own parent (A allows a1), the others have none.
  # child_value: :allowed stores a1 in every child, :blank stores nothing.
  def build_world(family:, managed:, total: managed, child_value: :allowed)
    tracker = dcf_tracker
    project = dcf_create_project
    project.trackers << tracker unless project.trackers.include?(tracker)
    dcf_add_member(member, project, role)
    parents = Array.new(total) { new_field(family) }
    children = parents.each_with_index.map do |parent, i|
      linked = i < managed
      child = new_field(family, depending: true, parent: linked ? parent : nil)
      next child unless linked

      dcf_set_dependencies(child, value_dependencies: { field_key(parent, 'A') => [field_key(child, 'a1')] })
    end
    (parents + children).each { |f| tracker.custom_fields << f }
    priority = IssuePriority.first || IssuePriority.create!(name: 'Normal')
    issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: member,
                      status: tracker.default_status, priority: priority)
    values = parents.to_h { |p| [p.id.to_s, field_key(p, 'A')] }
    children.each { |c| values[c.id.to_s] = child_value == :allowed ? field_key(c, 'a1') : '' }
    issue.custom_field_values = values
    issue.save!
    { issue: Issue.find(issue.id), parents: parents, children: children, values: values }
  end

  def edit_queries(world)
    issue = world[:issue]
    get "/issues/#{issue.id}/edit"
    expect(response).to have_http_status(200)
    count = dcf_count_queries { get "/issues/#{issue.id}/edit" }
    expect(response).to have_http_status(200)
    page = Nokogiri::HTML(response.body)
    world[:children].each do |child|
      expect(page.css("select#issue_custom_field_values_#{child.id}").size).to eq(1), "child #{child.id} not rendered"
    end
    count
  end

  # Submits every stored value unchanged, so core validates each custom value
  # (custom_field_values_changed?) without writing one.
  def update_queries(world)
    issue = world[:issue]
    params = { issue: { custom_field_values: world[:values] } }
    patch "/issues/#{issue.id}", params: params
    expect(response).to have_http_status(302)
    count = dcf_count_queries { patch "/issues/#{issue.id}", params: params }
    expect(response).to have_http_status(302)
    world[:children].each do |child|
      expect(Issue.find(issue.id).custom_field_value(child)).to eq(world[:values][child.id.to_s])
    end
    count
  end

  describe 'list children, 1 child of 1 parent vs 5 children of 5 distinct parents' do
    it 'renders the edit form with the same number of queries' do
      one = build_world(family: :list, managed: 1)
      five = build_world(family: :list, managed: 5)
      count_one = edit_queries(one)
      count_five = edit_queries(five)

      expect(count_one).to be > 0
      expect(count_five).to eq(count_one)
    end

    it 'validates and saves an update with the same number of queries' do
      one = build_world(family: :list, managed: 1)
      five = build_world(family: :list, managed: 5)
      count_one = update_queries(one)
      count_five = update_queries(five)

      expect(count_one).to be > 0
      expect(count_five).to eq(count_one)
    end
  end

  # Core runs one enumerations query per enumeration field, so both worlds
  # hold 5 parents and 5 children and differ only in how many children
  # depend on a parent (1 or 5). Since WP-08 the enumeration edit form builds
  # its options without the issue, as the list form does, so only the update
  # example reads the parent values.
  describe 'enumeration children, 1 managed child vs 5 managed children of distinct parents' do
    it 'renders the edit form with the same number of queries' do
      one = build_world(family: :enumeration, managed: 1, total: 5, child_value: :blank)
      five = build_world(family: :enumeration, managed: 5, total: 5, child_value: :blank)
      count_one = edit_queries(one)
      count_five = edit_queries(five)

      expect(count_one).to be > 0
      expect(count_five).to eq(count_one)
    end

    it 'validates and saves an update with the same number of queries' do
      one = build_world(family: :enumeration, managed: 1, total: 5)
      five = build_world(family: :enumeration, managed: 5, total: 5)
      count_one = update_queries(one)
      count_five = update_queries(five)

      expect(count_one).to be > 0
      expect(count_five).to eq(count_one)
    end
  end
end
