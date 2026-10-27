require_relative '../rails_helper'

RSpec.describe "DependingCustomFields API", type: :request do
  fixtures :users # admin is id:1 in Redmine fixtures

  before do
    allow(User).to receive(:current).and_return(User.find(1))
  end

  FIELD_TYPES = (DependingCustomFieldsApiController::CUSTOM_FIELD_CLASS_MAP.keys + ['CustomField', nil]).freeze

  def boolean
    satisfy { |v| v == true || v == false }
  end

  def expect_common_attributes(cf, name: nil, field_format: nil, type: nil)
    expect(cf).to include(
                    "id" => kind_of(Integer),
                    "name" => name || kind_of(String),
                    "type" => type || satisfy { |t| FIELD_TYPES.include?(t) },
                    "field_format" => field_format || kind_of(String),
                    "is_required" => boolean,
                    "is_filter" => boolean,
                    "searchable" => boolean,
                    "visible" => boolean,
                    "multiple" => boolean,
                    "default_value" => anything,
                    "url_pattern" => anything,
                    "edit_tag_style" => anything,
                    "is_for_all" => boolean,
                    "trackers" => kind_of(Array),
                    "projects" => kind_of(Array),
                    "roles" => kind_of(Array)
                  )
  end

  describe "GET /depending_custom_fields" do
    it "returns 200 and an array of fields" do
      get "/depending_custom_fields.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
      body.each { |cf| expect_common_attributes(cf) }
    end
  end

  describe "POST /depending_custom_fields" do
    it "creates a field and returns its data" do
      payload = {
        custom_field: {
          name: "spec field",
          type: "IssueCustomField",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          possible_values: ["A", "B"]
        }
      }

      expect {
        post "/depending_custom_fields.json", params: payload
      }.to change { CustomField.count }.by(1)

      expect(response).to have_http_status(:created)
      cf = JSON.parse(response.body)
      expect_common_attributes(cf, name: "spec field", field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, type: "IssueCustomField")
      expect(cf["possible_values"]).to eq(["A", "B"])
      expect(cf).to include(
        "parent_custom_field_id" => nil,
        "value_dependencies" => {},
        "default_value_dependencies" => {},
        "hide_when_disabled" => false
      )
      expect(cf).not_to have_key("enumerations")
    end

    it "creates a depending enumeration field and returns its enumerations" do
      payload = {
        custom_field: {
          name: "enum field",
          type: "IssueCustomField",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
          enumerations: [
            { name: "Option A", position: 1, active: true },
            { name: "Option B", position: 2, active: false }
          ]
        }
      }

      expect {
        post "/depending_custom_fields.json", params: payload
      }.to change { CustomField.count }.by(1)

      expect(response).to have_http_status(:created)
      cf = JSON.parse(response.body)

      expect_common_attributes(cf,
                               name: "enum field",
                               field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
                               type: "IssueCustomField")
      expect(cf).not_to have_key("possible_values")
      expect(cf["enumerations"]).to contain_exactly(
        a_hash_including("name" => "Option A", "position" => 1, "active" => true),
        a_hash_including("name" => "Option B", "position" => 2, "active" => false)
      )
    end

    it "rejects an invalid class name" do
      payload = {
        custom_field: {
          name: "spec field",
          type: "InvalidClass",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          possible_values: ["A", "B"]
        }
      }

      expect {
        post "/depending_custom_fields.json", params: payload
      }.not_to change { CustomField.count }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "allows setting a default value when no parent is set" do
      payload = {
        custom_field: {
          name: "with default",
          type: "IssueCustomField",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          possible_values: ["A", "B"],
          default_value: "B"
        }
      }

      post "/depending_custom_fields.json", params: payload
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["default_value"]).to eq("B")
    end

    it "creates an extended user field without dependency keys" do
      payload = {
        custom_field: {
          name: "extended",
          type: "UserCustomField",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER,
          group_ids: [1, "", 2],
          exclude_admins: true,
          show_active: false,
          show_registered: true,
          show_locked: false
        }
      }

      expect {
        post "/depending_custom_fields.json", params: payload
      }.to change { CustomField.count }.by(1)

      expect(response).to have_http_status(:created)
      cf = JSON.parse(response.body)

      expect_common_attributes(cf,
                               name: "extended",
                               field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER,
                               type: "UserCustomField")
      expect(cf).not_to have_key("possible_values")
      expect(cf).not_to have_key("enumerations")
      expect(cf).not_to have_key("value_dependencies")
      expect(cf).not_to have_key("default_value_dependencies")
      expect(cf).not_to have_key("hide_when_disabled")
      expect(cf["group_ids"]).to match_array([1, 2])
      expect(cf["exclude_admins"]).to eq(true)
      expect(cf["show_active"]).to eq(false)
      expect(cf["show_registered"]).to eq(true)
      expect(cf["show_locked"]).to eq(false)
    end
  end

  describe "PUT /depending_custom_fields/:id" do
    it "updates a field's name" do
      cf = CustomField.create!(
        name: "temp name",
        type: "IssueCustomField",
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        possible_values: ["A"]
      )

      payload = {
        custom_field: {
          name: "updated name"
        }
      }

      put "/depending_custom_fields/#{cf.id}.json", params: payload
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("updated name")
    end

    it "returns enumerations when updating a depending enumeration field" do
      cf = IssueCustomField.create!(
        name: "enum",
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
      )
      cf.enumerations.create!(name: "Initial", position: 1, active: true)

      payload = {
        custom_field: {
          enumerations: [
            { id: cf.enumerations.first.id, name: "Initial", position: 1, active: true },
            { name: "Added", position: 2, active: false }
          ]
        }
      }

      put "/depending_custom_fields/#{cf.id}.json", params: payload
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect_common_attributes(body,
                               name: "enum",
                               field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
                               type: "IssueCustomField")
      expect(body).not_to have_key("possible_values")
      expect(body["enumerations"]).to contain_exactly(
        a_hash_including("name" => "Initial", "position" => 1, "active" => true),
        a_hash_including("name" => "Added", "position" => 2, "active" => false)
      )
    end
  end

  describe "GET /depending_custom_fields/:id" do
    let!(:depending_list_field) do
      IssueCustomField.create!(
        name: "Depending list",
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        possible_values: %w[A B]
      ).tap do |field|
        field.update!(
          value_dependencies: { "1" => ["A"] },
          default_value_dependencies: { "1" => "A" },
          hide_when_disabled: true
        )
      end
    end

    let!(:depending_enum_field) do
      field = IssueCustomField.create!(
        name: "Depending enum",
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
      )
      field.enumerations.create!(name: "Opt 1", position: 1, active: true)
      field.enumerations.create!(name: "Opt 2", position: 2, active: false)
      field
    end

    let!(:extended_user_field) do
      UserCustomField.create!(
        name: "Extended user",
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER,
        group_ids: %w[1 2],
        exclude_admins: true,
        show_active: true,
        show_registered: false,
        show_locked: true
      )
    end

    it "includes dependency attributes only for depending list fields" do
      get "/depending_custom_fields/#{depending_list_field.id}.json"
      expect(response).to have_http_status(:ok)
      cf = JSON.parse(response.body)

      expect_common_attributes(cf, name: "Depending list", field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, type: "IssueCustomField")
      expect(cf["possible_values"]).to match_array(%w[A B])
      expect(cf["parent_custom_field_id"]).to be_nil
      expect(cf["value_dependencies"]).to eq({ "1" => ["A"] })
      expect(cf["default_value_dependencies"]).to eq({ "1" => "A" })
      expect(cf["hide_when_disabled"]).to eq(true)
      expect(cf).not_to have_key("enumerations")
      expect(cf).not_to have_key("group_ids")
    end

    it "includes enumeration data only for depending enumeration fields" do
      get "/depending_custom_fields/#{depending_enum_field.id}.json"
      expect(response).to have_http_status(:ok)
      cf = JSON.parse(response.body)

      expect_common_attributes(cf, name: "Depending enum", field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION, type: "IssueCustomField")
      expect(cf).not_to have_key("possible_values")
      expect(cf["enumerations"]).to contain_exactly(
        a_hash_including("name" => "Opt 1", "active" => true, "position" => 1),
        a_hash_including("name" => "Opt 2", "active" => false, "position" => 2)
      )
      expect(cf["value_dependencies"]).to eq({})
      expect(cf["default_value_dependencies"]).to eq({})
      expect(cf["hide_when_disabled"]).to eq(false)
    end

    it "includes extended user attributes without dependency data" do
      get "/depending_custom_fields/#{extended_user_field.id}.json"
      expect(response).to have_http_status(:ok)
      cf = JSON.parse(response.body)

      expect_common_attributes(cf, name: "Extended user", field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER, type: "UserCustomField")
      expect(cf).not_to have_key("possible_values")
      expect(cf).not_to have_key("enumerations")
      expect(cf).not_to have_key("value_dependencies")
      expect(cf).not_to have_key("default_value_dependencies")
      expect(cf).not_to have_key("hide_when_disabled")
      expect(cf["group_ids"]).to match_array([1, 2])
      expect(cf["exclude_admins"]).to eq(true)
      expect(cf["show_active"]).to eq(true)
      expect(cf["show_registered"]).to eq(false)
      expect(cf["show_locked"]).to eq(true)
    end
  end

  describe "DELETE /depending_custom_fields/:id" do
    it "deletes the field" do
      cf = CustomField.create!(
        name: "to delete",
        type: "IssueCustomField",
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        possible_values: ["A"]
      )

      expect {
        delete "/depending_custom_fields/#{cf.id}.json"
      }.to change { CustomField.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  # WP-10 (PC-10, PC-21, UD-08): a circular parent is a new 422 reason; the
  # payload shape, the other status codes and name-only round trips are
  # unchanged.
  describe "circular parents (WP-10)" do
    include DcfStoredCycle

    let(:circular_message) do
      "Depends on refers to this field or to one of its dependent fields, which would create a circular dependency"
    end

    def raw_store(field)
      CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
    end

    def put_field(field, attributes)
      put "/depending_custom_fields/#{field.id}.json", params: { custom_field: attributes }
    end

    it "answers 422 with the full message for the field's own id and stores nothing" do
      root = dcf_list_field
      field = dcf_list_field(format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, parent: root)
      before = raw_store(field)

      put_field(field, parent_custom_field_id: field.id.to_s)

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)).to eq("errors" => [circular_message])
      expect(raw_store(field)).to eq(before)
    end

    it "answers 422 for a parent change that closes a <-> b" do
      a = dcf_list_field(format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST)
      b = dcf_list_field(format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, parent: a)

      put_field(a, parent_custom_field_id: b.id.to_s, name: "renamed")

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)).to eq("errors" => [circular_message])
      expect(CustomField.find(a.id).parent_custom_field_id).to be_nil
      expect(CustomField.find(a.id).name).not_to eq("renamed")
    end

    it "keeps 200 with a null parent for an unknown parent id" do
      root = dcf_list_field
      field = dcf_list_field(format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, parent: root)

      put_field(field, parent_custom_field_id: (CustomField.maximum(:id).to_i + 1_000).to_s)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["parent_custom_field_id"]).to be_nil
      expect(CustomField.find(field.id).parent_custom_field_id).to be_nil
    end

    it "creates a field below a stored cycle (a new record is never refused)" do
      world = dcf_stored_cycles(:list)
      post "/depending_custom_fields.json", params: { custom_field: {
        name: "below", type: "IssueCustomField", field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        possible_values: %w[n1], parent_custom_field_id: world.x.id.to_s
      } }

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["parent_custom_field_id"]).to eq(world.x.id)
    end

    it "leaves the mapping byte-identical on a name-only PUT, also for a stored-cycle member" do
      root = dcf_list_field(values: %w[A B])
      field = dcf_list_field(format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, values: %w[a1 b1],
                             parent: root)
      mapping = { "A" => %w[a1 nope], "ZZ" => %w[nope], "[x]" => %w[b1], "a]" => %w[b1] }
      dcf_set_dependencies(field, value_dependencies: mapping, default_value_dependencies: { "ZZ" => "nope" })
      world = dcf_stored_cycles(:list)
      dcf_set_dependencies(world.x, value_dependencies: { "y1" => %w[x1], "ZZ" => %w[x2], "[x]" => %w[x1] })

      [field, world.x].each do |record|
        get "/depending_custom_fields/#{record.id}.json"
        keys = JSON.parse(response.body).keys
        before = CustomField.find(record.id).value_dependencies.to_hash.to_a
        raw_before = raw_store(record)

        put_field(record, name: "#{record.name}-renamed")

        expect(response).to have_http_status(:ok), response.body
        expect(JSON.parse(response.body).keys).to eq(keys)
        expect(CustomField.find(record.id).value_dependencies.to_hash.to_a).to eq(before)
        expect(raw_store(record)).to eq(raw_before)
      end
      expect(CustomField.find(world.x.id).parent_custom_field_id).to eq(world.y.id)
    end
  end

  # WP-11 (UN-32, PC-14, PC-21): a value list or mapping over the column limit
  # is a new 422 reason with the full model message, in the response shape of
  # every validation error; nothing is written.
  describe "storage limit (WP-11)" do
    let(:limits) { RedmineDependingCustomFields::StorageLimits }

    def raw_column(field, column)
      CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
    end

    def stub_limits(by_column)
      allow(limits).to receive(:column_limit).and_return(nil)
      by_column.each { |column, limit| allow(limits).to receive(:column_limit).with(column).and_return(limit) }
    end

    def capture_bytes
      captured = {}
      allow(limits).to receive(:preview_bytes).and_wrap_original do |original, record, column|
        captured[column] = original.call(record, column)
      end
      captured
    end

    def storage_message(attribute, bytes, limit)
      message = I18n.t("activerecord.errors.messages.dcf_storage_too_large",
                       size: limits.delimited(bytes), limit: limits.delimited(limit))
      "#{IssueCustomField.human_attribute_name(attribute)} #{message}"
    end

    it "answers 422 on create with the full message and creates nothing" do
      values = %w[A B C]
      bytes = limits.serialized_bytesize(CustomField, "possible_values", values)
      stub_limits("possible_values" => bytes - 1)

      expect do
        post "/depending_custom_fields.json", params: { custom_field: {
          name: "big list", type: "IssueCustomField", field_format: "list", possible_values: values
        } }
      end.not_to change { CustomField.count }

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)).to eq("errors" => [storage_message(:possible_values, bytes, bytes - 1)])
    end

    it "rolls back a create with enumerations (no field, no enumerations)" do
      parent = dcf_enum_field(names: %w[P])
      stub_limits("format_store" => 1)
      captured = capture_bytes

      expect do
        post "/depending_custom_fields.json", params: { custom_field: {
          name: "big enum", type: "IssueCustomField",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
          parent_custom_field_id: parent.id.to_s,
          value_dependencies: { parent.enumerations.first.id.to_s => %w[1] },
          enumerations: [{ name: "e1", position: 1, active: true }, { name: "e2", position: 2, active: true }]
        } }
      end.not_to change { [CustomField.count, CustomFieldEnumeration.count] }

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body))
        .to eq("errors" => [storage_message(:value_dependencies, captured.fetch("format_store"), 1)])
    end

    it "answers 422 on update and leaves the columns and the enumerations unchanged" do
      parent = dcf_enum_field(names: %w[P Q])
      field = dcf_enum_field(format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
                             names: %w[c1 c2], parent: parent)
      before = %w[possible_values format_store].map { |c| raw_column(field, c) }
      names = field.enumerations.order(:id).pluck(:id, :name, :position)
      stub_limits("format_store" => 1)
      captured = capture_bytes

      put "/depending_custom_fields/#{field.id}.json", params: { custom_field: {
        name: "#{field.name}-x",
        value_dependencies: { parent.enumerations.first.id.to_s => [field.enumerations.first.id.to_s] },
        enumerations: [{ id: field.enumerations.first.id, name: "renamed", position: 1, active: true }]
      } }

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body))
        .to eq("errors" => [storage_message(:value_dependencies, captured.fetch("format_store"), 1)])
      expect(%w[possible_values format_store].map { |c| raw_column(field, c) }).to eq(before)
      expect(CustomField.find(field.id).name).to eq(field.name)
      expect(field.enumerations.order(:id).pluck(:id, :name, :position)).to eq(names)
    end

    it "answers 422 for a possible_values update sent as a JSON body" do
      field = dcf_list_field(values: %w[A B])
      before = raw_column(field, "possible_values")
      values = Array.new(50) { |i| "value #{i}" }
      bytes = limits.serialized_bytesize(CustomField, "possible_values", values)
      stub_limits("possible_values" => bytes - 1)

      put "/depending_custom_fields/#{field.id}.json", params: { custom_field: { possible_values: values } }.to_json,
                                                        headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)).to eq("errors" => [storage_message(:possible_values, bytes, bytes - 1)])
      expect(raw_column(field, "possible_values")).to eq(before)
    end

    it "keeps 200 and the response keys at the limit" do
      field = dcf_list_field(values: %w[A B])
      get "/depending_custom_fields/#{field.id}.json"
      keys = JSON.parse(response.body).keys
      values = %w[A B C]
      stub_limits("possible_values" => limits.serialized_bytesize(CustomField, "possible_values", values))

      put "/depending_custom_fields/#{field.id}.json", params: { custom_field: { possible_values: values } }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).keys).to eq(keys)
      expect(CustomField.find(field.id).possible_values).to eq(values)
    end
  end

  # WP-22 (editor design 3.2, compat 2.2): the plugin API does not permit the
  # admin transport field. A posted dependencies_json is dropped by the strong
  # parameters: nothing is parsed, cleared, pruned or refused, and the
  # response keys stay the same.
  describe "dependencies_json (WP-22)" do
    let(:dependency_payload) { RedmineDependingCustomFields::DependencyPayload }
    let(:root) { dcf_list_field(values: %w[A B]) }
    let(:field) do
      record = dcf_list_field(format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, values: %w[a1 b1],
                              parent: root)
      dcf_set_dependencies(record, value_dependencies: { "B" => %w[b1], "A" => %w[a1 nope], "ZZ" => %w[nope] },
                                   default_value_dependencies: { "ZZ" => "nope" })
    end

    def raw_store(record)
      CustomField.connection.select_value(CustomField.where(id: record.id).select(:format_store).to_sql)
    end

    it "ignores it on update: no clear, no error and the same response keys" do
      get "/depending_custom_fields/#{field.id}.json"
      keys = JSON.parse(response.body).keys
      raw_before = raw_store(field)
      allow(dependency_payload).to receive(:parse).and_call_original

      ["{}", "{", "{\"value_dependencies\":{\"A\":[#{'9' * 100_000}]}}", { "value_dependencies" => "1" }]
        .each_with_index do |raw, i|
        put "/depending_custom_fields/#{field.id}.json",
            params: { custom_field: { name: "#{field.name}-#{i}", dependencies_json: raw } }

        expect(response).to have_http_status(:ok), response.body
        body = JSON.parse(response.body)
        expect(body.keys).to eq(keys)
        expect(body).not_to have_key("dependencies_json")
        expect(CustomField.find(field.id).name).to eq("#{field.name}-#{i}")
        expect(raw_store(field)).to eq(raw_before)
      end
      expect(dependency_payload).not_to have_received(:parse)
    end

    it "ignores it on create and stores the nested mapping sanitize-only" do
      allow(dependency_payload).to receive(:parse).and_call_original

      post "/depending_custom_fields.json", params: { custom_field: {
        name: "api-#{SecureRandom.hex(3)}", type: "IssueCustomField",
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, possible_values: %w[a1 b1],
        parent_custom_field_id: root.id.to_s, value_dependencies: { "ZZ" => %w[nope], "A" => %w[a1] },
        dependencies_json: "{}"
      } }

      expect(response).to have_http_status(:created), response.body
      body = JSON.parse(response.body)
      expect(body).not_to have_key("dependencies_json")
      expect(CustomField.find(body["id"]).value_dependencies.to_hash).to eq("ZZ" => %w[nope], "A" => %w[a1])
      expect(dependency_payload).not_to have_received(:parse)
    end
  end
end
