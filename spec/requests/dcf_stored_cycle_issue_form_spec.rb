# frozen_string_literal: true

require_relative '../rails_helper'

# WP-10 semantics-r2-1: fields in or below a stored cycle have no effective
# parent and are unconstrained (UD-08, UD-35), but until WP-18 retires the
# legacy script the issue form still disables such a field while its stored
# parent value allows nothing and posts '' for it. The required bypass
# (DependencyRules.no_options?) therefore keeps the 0.0.16 parent read for
# them, so a new issue with required fields of that kind still saves, as it
# did in 0.0.16.
RSpec.describe 'New issues with required fields in or below a stored cycle', type: :request do
  include DcfStoredCycle

  fixtures :users

  let(:project) { dcf_create_project }

  before { allow(User).to receive(:current).and_return(dcf_admin) }

  [:list, :enumeration].each do |kind|
    it "saves a #{kind} issue form post that sends '' for the required member, self-parent and fields below them" do
      world = dcf_stored_cycles(kind)
      required = [world.x, world.child, world.self_parent, world.below_self_parent]
      CustomField.where(id: required.map(&:id)).update_all(is_required: true)
      tracker, _status, priority = dcf_issue_infra(project)
      world.depending.each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
      values = world.depending.to_h { |f| [f.id.to_s, ''] }

      expect do
        post "/projects/#{project.identifier}/issues",
             params: { issue: { tracker_id: tracker.id, subject: 'Stored cycle', priority_id: priority.id,
                                custom_field_values: values } }
      end.to change(Issue, :count).by(1)
      expect(response).to have_http_status(302)
      issue = Issue.order(:id).last
      expect(required.map { |f| issue.custom_field_value(f).to_s }).to eq(['', '', '', ''])
    end
  end

  it 'still refuses a blank required member while its stored partner value allows a value' do
    world = dcf_stored_cycles(:list)
    CustomField.where(id: world.y.id).update_all(is_required: true)
    tracker, _status, priority = dcf_issue_infra(project)
    [world.x, world.y].each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }

    expect do
      post "/projects/#{project.identifier}/issues",
           params: { issue: { tracker_id: tracker.id, subject: 'Stored cycle', priority_id: priority.id,
                              custom_field_values: { world.x.id.to_s => 'x1', world.y.id.to_s => '' } } }
    end.not_to change(Issue, :count)
    expect(Nokogiri::HTML(response.body).css('#errorExplanation').text)
      .to include("#{world.y.name} #{I18n.t('activerecord.errors.messages.blank')}")
  end
end
