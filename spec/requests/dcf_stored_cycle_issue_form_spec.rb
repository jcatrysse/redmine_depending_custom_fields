# frozen_string_literal: true

require_relative '../rails_helper'

# WP-10 semantics-r2-1, flipped by WP-18 (WP-10 open input): fields in or
# below a stored cycle have no effective parent and are unconstrained (UD-08,
# UD-35). The legacy script used to disable such a field while its stored
# parent value allowed nothing and post '' for it, so the required bypass
# (DependencyRules.no_options?) kept the 0.0.16 parent read for them. WP-18
# removes the legacy script and that fallback: the new runtime gives these
# fields no parent attributes, so the user can pick a value, and core's
# required check applies to them.
RSpec.describe 'New issues with required fields in or below a stored cycle', type: :request do
  include DcfStoredCycle

  fixtures :users

  let(:project) { dcf_create_project }

  before { allow(User).to receive(:current).and_return(dcf_admin) }

  def post_issue(tracker, priority, values)
    post "/projects/#{project.identifier}/issues",
         params: { issue: { tracker_id: tracker.id, subject: 'Stored cycle', priority_id: priority.id,
                            custom_field_values: values } }
  end

  [:list, :enumeration].each do |kind|
    # Flipped by WP-18: was "saves a #{kind} issue form post that sends ''
    # for the required member, self-parent and fields below them".
    it "refuses a #{kind} issue form post that sends '' for the required member, self-parent and fields below them" do
      world = dcf_stored_cycles(kind)
      required = [world.x, world.child, world.self_parent, world.below_self_parent]
      CustomField.where(id: required.map(&:id)).update_all(is_required: true)
      tracker, _status, priority = dcf_issue_infra(project)
      world.depending.each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
      values = world.depending.to_h { |f| [f.id.to_s, ''] }

      expect { post_issue(tracker, priority, values) }.not_to change(Issue, :count)
      errors = Nokogiri::HTML(response.body).css('#errorExplanation').text
      required.each do |field|
        expect(errors).to include("#{field.name} #{I18n.t('activerecord.errors.messages.blank')}"), field.name
      end
    end

    it "saves a #{kind} issue form post that sends values for the required members, also values no mapping allows" do
      world = dcf_stored_cycles(kind)
      required = [world.x, world.child, world.self_parent, world.below_self_parent]
      CustomField.where(id: required.map(&:id)).update_all(is_required: true)
      tracker, _status, priority = dcf_issue_infra(project)
      world.depending.each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
      names = { world.x => 'x2', world.child => 'c2', world.self_parent => 's2', world.below_self_parent => 'd2' }
      values = world.depending.to_h { |f| [f.id.to_s, ''] }
      names.each { |field, name| values[field.id.to_s] = kit_key(field, name) }

      expect { post_issue(tracker, priority, values) }.to change(Issue, :count).by(1)
      expect(response).to have_http_status(302)
      issue = Issue.order(:id).last
      expect(required.map { |f| issue.custom_field_value(f).to_s }).to eq(names.map { |f, name| kit_key(f, name) })
    end
  end

  it 'still refuses a blank required member while its stored partner value allows a value' do
    world = dcf_stored_cycles(:list)
    CustomField.where(id: world.y.id).update_all(is_required: true)
    tracker, _status, priority = dcf_issue_infra(project)
    [world.x, world.y].each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }

    expect do
      post_issue(tracker, priority, { world.x.id.to_s => 'x1', world.y.id.to_s => '' })
    end.not_to change(Issue, :count)
    expect(Nokogiri::HTML(response.body).css('#errorExplanation').text)
      .to include("#{world.y.name} #{I18n.t('activerecord.errors.messages.blank')}")
  end
end
