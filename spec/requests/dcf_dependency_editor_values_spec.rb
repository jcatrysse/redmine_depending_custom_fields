# frozen_string_literal: true

require_relative '../rails_helper'

# WP-24 (editor design 4.1 and 4.2, AD-7, quality G5): GET
# /dcf_dependency_editor/values, the values of a candidate parent field for
# the dependency editor. Admin only, session only: no API key, no format, no
# lookup before require_admin. Every authentication example logs in through
# POST /login, never with a User.current stub, so the session and API-key
# rules of core find_current_user are what these examples prove.
RSpec.describe 'GET /dcf_dependency_editor/values (WP-24)', type: :request do
  fixtures :users

  let(:path) { '/dcf_dependency_editor/values' }
  let(:admin) { User.find(1) }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:config) { RedmineDependingCustomFields::DependencyEditorConfig }
  let(:list_parent) { dcf_list_field(name: 'Country', values: %w[Germany Belgium France]) }
  # Positions are written after creation (acts_as_positioned renumbers on
  # create): North and South share a position, so their ids order them.
  let(:enum_parent) do
    field = dcf_enum_field(name: 'Region', names: [])
    { 'North' => [2, true], 'Old' => [1, false], 'South' => [2, true] }.each do |name, (position, active)|
      entry = CustomFieldEnumeration.create!(custom_field_id: field.id, name: name, active: active)
      entry.update_columns(position: position)
    end
    CustomField.find(field.id)
  end
  let(:not_found) { { 'error' => 'not_found' } }

  def log_in(user, password)
    post '/login', params: { username: user.login, password: password }
    expect(response).to have_http_status(:redirect)
    expect(session[:user_id]).to eq(user.id)
  end

  def member_user(password = 'secret-12345')
    login = "dcfed-#{SecureRandom.hex(3)}"
    user = User.new(login: login, firstname: 'F', lastname: 'L', mail: "#{login}@example.net",
                    status: User::STATUS_ACTIVE)
    user.password = password
    user.password_confirmation = password
    user.save!
    dcf_add_member(user, dcf_create_project, dcf_create_role(permissions: [:view_issues]))
    user
  end

  def query(field, kind: rules.kind(field), type: field.type)
    { custom_field_id: field.id.to_s, kind: kind, type: type }
  end

  def body_json
    JSON.parse(response.body)
  end

  def enum_key(field, name)
    field.enumerations.detect { |e| e.name == name }.id.to_s
  end

  # The admin presenter of a depending child of +parent+, rendered in a
  # CustomFieldsController view context.
  def presenter_parent_values(parent)
    format = rules.kind(parent) == 'list' ? 'depending_list' : 'depending_enumeration'
    name = "Child of #{parent.name}"
    child = if format == 'depending_list'
              dcf_list_field(format: format, name: name, values: %w[c1], parent: parent)
            else
              dcf_enum_field(format: format, name: name, names: %w[c1], parent: parent)
            end
    controller = CustomFieldsController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    view = controller.view_context
    attributes = config.for_admin(CustomField.find(child.id), view).data_attributes
    html = view.content_tag(:fieldset, '', data: attributes)
    JSON.parse(Nokogiri::HTML5.fragment(html).at_css('fieldset')['data-dcf-editor-parent-values'])
  end

  describe 'route' do
    it 'routes GET /dcf_dependency_editor/values to the values action, outside depending_custom_fields/:id' do
      expect(Rails.application.routes.recognize_path(path, method: :get))
        .to eq(controller: 'dcf_dependency_editor', action: 'values')
      expect(Rails.application.routes.url_helpers.dcf_dependency_editor_values_path).to eq(path)
      expect(Rails.application.routes.recognize_path('/depending_custom_fields/values', method: :get))
        .to eq(controller: 'depending_custom_fields_api', action: 'show', id: 'values', format: 'json')
    end

    it 'routes no other verb' do
      [:post, :put, :patch, :delete].each do |verb|
        expect { Rails.application.routes.recognize_path(path, method: verb) }
          .to raise_error(ActionController::RoutingError), verb.to_s
      end
    end

    it 'has no json format default (the .json path is routable and stays an API request)' do
      expect(Rails.application.routes.recognize_path(path, method: :get)).not_to have_key(:format)
      expect(Rails.application.routes.recognize_path("#{path}.json", method: :get))
        .to eq(controller: 'dcf_dependency_editor', action: 'values', format: 'json')
    end
  end

  describe 'the controller' do
    it 'runs require_admin first and accepts no API, atom or rss key' do
      controller = DcfDependencyEditorController
      filters = controller._process_action_callbacks.select { |c| c.kind == :before }.map(&:filter)
      expect(filters.last).to eq(:require_admin)
      expect(filters.count(:require_admin)).to eq(1)
      expect(controller.accept_api_auth).to eq([])
      expect(controller.accept_atom_auth).to eq([])
      expect(controller.public_instance_methods(false)).to eq([:values])
      source = File.read(File.expand_path('../../app/controllers/dcf_dependency_editor_controller.rb', __dir__))
      expect(source).not_to match(/accept_api_auth|accept_atom_auth|accept_rss_auth|skip_before_action|skip_forgery_protection|protect_from_forgery|constantize|html_safe|raw\(/)
    end
  end

  describe 'as an administrator' do
    before { log_in(admin, 'admin') }

    it 'returns a list field as {id, name, kind, values} with {key} entries in possible_values order' do
      get path, params: query(list_parent)

      expect(response).to have_http_status(200)
      expect(response.media_type).to eq('application/json')
      expect(response.body).to start_with('{')
      expect(body_json.keys).to eq(%w[id name kind values])
      expect(body_json).to eq('id' => list_parent.id, 'name' => 'Country', 'kind' => 'list',
                              'values' => [{ 'key' => 'Germany' }, { 'key' => 'Belgium' }, { 'key' => 'France' }])
      expect(body_json['values']).to all(satisfy { |entry| entry.keys == ['key'] })
    end

    it 'drops a repeated list value, the first one kept' do
      field = dcf_list_field(name: 'Repeated', values: %w[B A B C])
      get path, params: query(field)

      expect(body_json['values']).to eq([{ 'key' => 'B' }, { 'key' => 'A' }, { 'key' => 'C' }])
    end

    it 'returns an enumeration by [position, id] with labels, inactive entries included with active false only' do
      field = enum_parent
      named_like_id = CustomFieldEnumeration.create!(custom_field_id: field.id, name: 'tmp', active: true)
      named_like_id.update_columns(name: named_like_id.id.to_s, position: 3)
      get path, params: query(CustomField.find(field.id))

      expect(response).to have_http_status(200)
      expect(body_json['kind']).to eq('enumeration')
      expect(body_json['values']).to eq(
        [{ 'key' => enum_key(field, 'Old'), 'label' => 'Old', 'active' => false },
         { 'key' => enum_key(field, 'North'), 'label' => 'North' },
         { 'key' => enum_key(field, 'South'), 'label' => 'South' },
         { 'key' => named_like_id.id.to_s }]
      )
      expect(body_json['values'].flat_map(&:values)).not_to include(true)
    end

    it 'serves a depending field of the family and the wire shape of wire_values(value_options(cf))' do
      depending = dcf_enum_field(format: 'depending_enumeration', name: 'Depending', names: %w[X Y], parent: enum_parent)
      get path, params: query(depending)

      expect(body_json['kind']).to eq('enumeration')
      expect(body_json['values']).to eq(config.wire_values(rules.value_options(depending)))
      expect(body_json['values'].map { |v| v['label'] }).to eq(%w[X Y])
    end

    it 'answers an XHR with Accept application/json (the session path) with 200' do
      get path, params: query(list_parent), headers: { 'X-Requested-With' => 'XMLHttpRequest',
                                                       'Accept' => 'application/json' }

      expect(response).to have_http_status(200)
      expect(body_json['name']).to eq('Country')
    end

    it 'gives the same values as the admin presenter data-dcf-editor-parent-values (list and enumeration)' do
      [list_parent, enum_parent].each do |parent|
        get path, params: query(parent)
        expect(response).to have_http_status(200)
        expect(body_json['values']).to eq(presenter_parent_values(parent)), parent.name
      end
    end

    it 'ignores a callback parameter and sends no CORS or public cache header' do
      get path, params: query(list_parent).merge(callback: 'steal')

      expect(response.body).to start_with('{"id":')
      expect(response.media_type).to eq('application/json')
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
      expect(response.headers['Cache-Control'].to_s).not_to include('public')
    end

    context 'with a request it cannot answer' do
      let(:string_field) { IssueCustomField.create!(name: 'Text', field_format: 'string') }
      let(:project_list) { dcf_list_field(name: 'Project list', values: %w[P], type: ProjectCustomField) }

      def bad_requests
        id = list_parent.id.to_s
        good = query(list_parent)
        [
          {}, good.except(:custom_field_id), good.merge(custom_field_id: ''), good.merge(custom_field_id: '0'),
          good.merge(custom_field_id: '-1'), good.merge(custom_field_id: "0#{id}"), good.merge(custom_field_id: "#{id}abc"),
          good.merge(custom_field_id: " #{id}"), good.merge(custom_field_id: '9' * 25), good.merge(custom_field_id: [id]),
          good.merge(custom_field_id: { 'a' => id }), good.merge(custom_field_id: '999999999'),
          good.except(:kind), good.merge(kind: ''), good.merge(kind: 'string'), good.merge(kind: '__proto__'),
          good.merge(kind: 'user'), good.merge(kind: ['list']), good.merge(kind: 'enumeration'),
          query(enum_parent, kind: 'list'),
          good.except(:type), good.merge(type: ''), good.merge(type: 'ProjectCustomField'),
          good.merge(type: 'TimeEntryCustomField'), good.merge(type: { 'x' => 'y' }), good.merge(type: 'CustomField'),
          query(project_list, type: 'IssueCustomField'),
          query(string_field, kind: 'list'), query(string_field, kind: nil), query(string_field, kind: 'enumeration')
        ]
      end

      it 'answers 404 with exactly {"error":"not_found"} and nothing else, never 500' do
        bad_requests.each do |params|
          get path, params: params

          label = params.inspect
          expect(response).to have_http_status(404), label
          expect(response.media_type).to eq('application/json'), label
          expect(body_json).to eq(not_found), label
        end
      end

      it 'puts no field name, value or database text into a 404' do
        get path, params: query(list_parent, kind: 'enumeration')

        expect(response.body).to eq('{"error":"not_found"}')
      end
    end

    it 'runs the same number of queries for 3 and 300 enumerations and for 3 and 2,000 list values (G6)' do
      small_enum = dcf_enum_field(name: 'Small', names: %w[A B C])
      large_enum = dcf_enum_field(name: 'Large', names: [])
      CustomFieldEnumeration.insert_all((1..300).map { |i| { custom_field_id: large_enum.id, name: "E#{i}", position: i, active: true } })
      small_list = dcf_list_field(name: 'Small list', values: %w[a b c])
      large_list = dcf_list_field(name: 'Large list', values: (1..2_000).map { |i| "v#{i}" })
      get path, params: query(small_enum)
      get path, params: query(small_list)

      counts = [small_enum, CustomField.find(large_enum.id), small_list, large_list].map do |field|
        dcf_count_queries { get path, params: query(field) }
      end
      expect(response).to have_http_status(200)
      expect(body_json['values'].size).to eq(2_000)
      expect(counts[0]).to eq(counts[1])
      expect(counts[2]).to eq(counts[3])
    end
  end

  describe 'as a logged-in user who is not an administrator' do
    let(:user) { member_user }

    before { log_in(user, 'secret-12345') }

    it 'answers 403 to every input before any field lookup, with no field data' do
      allow(CustomField).to receive(:find_by).and_call_original
      allow(rules).to receive(:value_options).and_call_original
      field = list_parent
      [query(field), query(field).merge(custom_field_id: '999999999'), query(field, kind: 'enumeration'), {}].each do |params|
        get path, params: params

        expect(response).to have_http_status(403), params.inspect
        expect(response.body).not_to include('Country')
        expect(response.body).not_to include('Belgium')
        expect(response.body).not_to include('not_found')
      end
      expect(CustomField).not_to have_received(:find_by).with(hash_including(id: field.id))
      expect(rules).not_to have_received(:value_options)
    end

    it 'answers 403 with an empty body to an XHR, also with an administrator API key' do
      allow(Setting).to receive(:rest_api_enabled?).and_return(true)
      get path, params: query(list_parent), headers: { 'X-Requested-With' => 'XMLHttpRequest',
                                                       'Accept' => 'application/json',
                                                       'X-Redmine-API-Key' => admin.api_key }

      expect(response).to have_http_status(403)
      expect(response.body).to eq('')
    end
  end

  describe 'without a session' do
    it 'answers 401 with an empty body and a Basic challenge to an XHR (Rails xhr, Accept text/javascript first)' do
      get path, params: query(list_parent), xhr: true

      expect(response).to have_http_status(401)
      expect(response.body).to eq('')
      # Core format.js: the Basic challenge a browser may answer with a login prompt.
      expect(response.headers['WWW-Authenticate']).to include('Basic')
    end

    it 'redirects a browser request to the login page' do
      get path, params: query(list_parent)

      expect(response).to have_http_status(302)
      expect(response.location).to include('/login')
    end

    it 'answers 403 without a challenge to an XHR that accepts JSON (core format.api branch, no accept_api_auth)' do
      get path, params: query(list_parent), headers: { 'X-Requested-With' => 'XMLHttpRequest',
                                                       'Accept' => 'application/json' }

      expect(response).to have_http_status(403)
      expect(response.body).to eq('')
      # No challenge, so no browser login prompt (the fetch headers WP-25 uses).
      expect(response.headers['WWW-Authenticate']).to be_nil
    end

    it 'never authenticates an API key, HTTP Basic or a key parameter, with or without .json' do
      allow(Setting).to receive(:rest_api_enabled?).and_return(true)
      key = admin.api_key
      basic = ActionController::HttpAuthentication::Basic.encode_credentials('admin', 'admin')
      attempts = [
        [path, query(list_parent), { 'X-Redmine-API-Key' => key }],
        [path, query(list_parent).merge(key: key), {}],
        [path, query(list_parent), { 'Authorization' => basic }],
        ["#{path}.json", query(list_parent), { 'X-Redmine-API-Key' => key }],
        ["#{path}.json", query(list_parent).merge(key: key), {}],
        ["#{path}.json", query(list_parent), { 'Authorization' => basic }],
        ["#{path}.atom", query(list_parent).merge(key: admin.atom_key), {}]
      ]
      attempts.each do |url, params, headers|
        [false, true].each do |xhr|
          get url, params: params, headers: headers, xhr: xhr
          label = "#{url} #{headers.keys.join(',')} key=#{params.key?(:key)} xhr=#{xhr}"
          expect([302, 401, 403]).to include(response.status), label
          expect(response.body).not_to include('"values"'), label
          expect(response.body).not_to include('Germany'), label
        end
      end
      get path, params: query(list_parent), headers: { 'X-Redmine-API-Key' => key }, xhr: true
      expect(response).to have_http_status(401)
      get "#{path}.json", params: query(list_parent), headers: { 'X-Redmine-API-Key' => key }
      expect(response).to have_http_status(403)
    end
  end

  # Changed by WP-25: the admin format partials render the editor (was:
  # 'is rendered by no production view yet'). Changed by WP-27: the project
  # dependency page renders it too (was: the two admin partials only).
  describe 'the editor partial' do
    it 'is rendered by the admin format partials and the project dependency page' do
      log_in(admin, 'admin')
      child = dcf_list_field(format: 'depending_list', name: 'Wired child', values: %w[c1], parent: list_parent)
      get "/custom_fields/#{child.id}/edit"

      expect(response).to have_http_status(200)
      expect(Nokogiri::HTML(response.body).css('fieldset[data-dcf-editor]').size).to eq(1)
      project = dcf_create_project
      get "/projects/#{project.identifier}/custom_field_configuration/fields/#{child.id}/dependencies"
      expect(response).to have_http_status(200)
      expect(Nokogiri::HTML(response.body).css('fieldset[data-dcf-editor][data-dcf-editor-mode="project"]').size)
        .to eq(1)
      root = File.expand_path('../..', __dir__)
      users = Dir[File.join(root, 'app', '**', '*.{rb,erb}')].select do |path|
        File.read(path).match?(/dependency_editor|DependencyEditorConfig/)
      end
      expect(users.map { |path| path.delete_prefix("#{root}/") })
        .to contain_exactly('app/controllers/dcf_dependency_editor_controller.rb',
                            'app/views/depending_custom_fields/_dependency_editor.html.erb',
                            'app/views/custom_fields/formats/_depending_list.html.erb',
                            'app/views/custom_fields/formats/_depending_enumeration.html.erb',
                            'app/views/project_custom_field_configuration/edit_dependencies.html.erb')
    end
  end

  describe 'with an administrator session on a format request' do
    before { log_in(admin, 'admin') }

    it 'is not session-authenticated for .json, ?format=json or .xml (API request, no accept_api_auth)' do
      [["#{path}.json", query(list_parent)], [path, query(list_parent).merge(format: 'json')],
       ["#{path}.xml", query(list_parent)]].each do |url, params|
        get url, params: params

        expect(response).to have_http_status(403), url
        expect(response.body).not_to include('"values"'), url
        expect(response.body).not_to include('Germany'), url
        expect(response.headers['WWW-Authenticate']).to be_nil, url
      end
    end
  end
end
