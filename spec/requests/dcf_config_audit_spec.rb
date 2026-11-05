require_relative '../rails_helper'

RSpec.describe 'Global config audit view', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  it 'is accessible to an admin (T-SEC-9)' do
    RedmineDependingCustomFields::ConfigAuditEvent.create!(action: 'add_value', status: 'success', created_at: Time.now)
    as(dcf_admin)
    get dcf_config_audit_path
    expect(response).to have_http_status(:ok)
  end

  it 'is forbidden to a non-admin permission holder (T-SEC-9)' do
    as(dcf_manager(project))
    get dcf_config_audit_path
    expect(response).to have_http_status(:forbidden)
  end

  it 'is forbidden to an anonymous-like non-member' do
    as(dcf_create_user('nobody'))
    get dcf_config_audit_path
    expect(response).to have_http_status(:forbidden)
  end

  # WP-32 (WP-28 input 4, project design 4): the page loads only the listed
  # columns and reads the page like the project audit action.
  describe 'page query and page parameter (WP-32)' do
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }

    def doc
      Nokogiri::HTML(response.body)
    end

    def cells(row)
      row.css('td').map { |td| td.text.strip }
    end

    def seed(count)
      count.times do |i|
        events.create!(project_id: project.id, action: 'rename_value', status: 'success',
                       custom_field_name: "F#{i}", acting_user_name: 'M', changes_summary: "<b>S#{i}</b>",
                       before_value: 'x' * 16_384, after_value: 'y' * 16_384, created_at: Time.now - i)
      end
    end

    before { as(dcf_admin) }

    it 'selects only the listed columns, counts every row and renders the rows unchanged' do
      seed(60)
      sqls = []
      callback = lambda do |*, payload|
        sqls << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached]
      end
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { get dcf_config_audit_path }

      expect(response).to have_http_status(200)
      audit = sqls.grep(/dcf_config_audit_events/)
      row_sql = audit.find { |sql| sql =~ /LIMIT/i && sql !~ /COUNT\(/i }
      expect(row_sql).to be_present
      expect(row_sql).not_to match(/before_value|after_value|affected_child_field_ids|\.\*|SELECT \*/)
      expect(audit.grep(/COUNT\(\*\)/i)).not_to be_empty
      rows = doc.css('table.dcf-audit-list tbody tr')
      expect(rows.size).to eq(50)
      # Changed by the Chromium walkthrough of 2026-11-05 (ux-3): translated
      # action and status; were the stored keys.
      expect(cells(rows.first)[1..]).to eq([project.name, 'M', 'F0', I18n.t(:label_dcf_audit_action_rename_value),
                                            I18n.t(:label_dcf_audit_status_success), '<b>S0</b>'])
      expect(response.body).to include('&lt;b&gt;S0&lt;/b&gt;')
      expect(response.body).not_to include('&amp;lt;')
      expect(doc.css('span.pagination span.items').text).to eq('(1-50/60)')
      get dcf_config_audit_path(page: '2')
      expect(doc.css('span.pagination span.items').text).to eq('(51-60/60)')
    end

    # Changed by the Chromium walkthrough of 2026-11-05 (ux-3): the action,
    # the status and the error are shown translated; were the stored keys.
    it 'shows the error message and the id of a deleted project' do
      events.create!(project_id: 999_999, action: 'add_value', status: 'validation_failed',
                     custom_field_name: 'Gone', acting_user_name: 'M', error_message: 'error_value_blank',
                     created_at: Time.now)
      get dcf_config_audit_path
      expect(cells(doc.at_css('table.dcf-audit-list tbody tr'))[1..])
        .to eq(['999999', 'M', 'Gone', I18n.t(:label_dcf_audit_action_add_value),
                I18n.t(:label_dcf_audit_status_validation_failed), I18n.t(:error_value_blank)])
    end

    it 'answers an Array, a Hash or a junk page with page 1 instead of a 500' do
      seed(60)
      ['page[]=1', 'page[x]=1', 'page=abc', 'page=0', 'page=-1'].each do |query|
        get "#{dcf_config_audit_path}?#{query}"
        expect(response).to have_http_status(200), query
        expect(doc.css('span.pagination span.items').text).to eq('(1-50/60)'), query
      end
    end

    it 'keeps the filters on custom_field_id, action_filter and project_id' do
      other = dcf_create_project(name: 'Other')
      events.create!(project_id: project.id, custom_field_id: 7, action: 'add_value', status: 'success',
                     custom_field_name: 'Kept', created_at: Time.now)
      events.create!(project_id: other.id, custom_field_id: 7, action: 'add_value', status: 'success',
                     custom_field_name: 'Other project', created_at: Time.now)
      events.create!(project_id: project.id, custom_field_id: 8, action: 'rename_value', status: 'success',
                     custom_field_name: 'Other field', created_at: Time.now)
      get dcf_config_audit_path(custom_field_id: 7, action_filter: 'add_value', project_id: project.id)
      expect(doc.css('table.dcf-audit-list tbody tr').map { |row| cells(row)[3] }).to eq(['Kept'])
    end
  end
end
