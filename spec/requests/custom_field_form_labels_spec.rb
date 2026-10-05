# frozen_string_literal: true

require_relative '../rails_helper'

# The per-parent default table of the admin custom field form used the key
# label_default_value, which exists in no locale ("translation missing").
RSpec.describe 'Admin custom field form labels', type: :request do
  fixtures :users

  before { allow(User).to receive(:current).and_return(dcf_admin) }

  it 'shows the core "Default value" header in the per-parent default table' do
    parent = dcf_list_field(values: %w[A B])
    child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })

    get "/custom_fields/#{child.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('dependencies-defaults')
    expect(response.body).to include(I18n.t(:field_default_value, locale: :en))
    expect(response.body).not_to include('translation missing')
  end
end
