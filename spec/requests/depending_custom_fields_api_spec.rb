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
        "parent_field_type" => nil,
        "parent_field_key" => nil,
        "value_dependencies" => {},
        "default_value_dependencies" => {},
        "dependency_rules" => [],
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

    it "rejects invalid dependency rules" do
      payload = {
        custom_field: {
          name: "rule field",
          type: "IssueCustomField",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          possible_values: ["A"],
          dependency_rules: "invalid-json"
        }
      }

      expect {
        post "/depending_custom_fields.json", params: payload
      }.not_to change { CustomField.count }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"]).to have_key("dependency_rules")
      expect(body["errors"]["dependency_rules"]["base"].first).to include("code" => "invalid_json")
    end

    it "rejects dependency rules missing child_values" do
      payload = {
        custom_field: {
          name: "rule field",
          type: "IssueCustomField",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          possible_values: ["A"],
          dependency_rules: [{ operator: "equals", value: "A" }]
        }
      }

      expect {
        post "/depending_custom_fields.json", params: payload
      }.not_to change { CustomField.count }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"]).to have_key("dependency_rules")
      expect(body["errors"]["dependency_rules"]["0"].first).to include("code" => "missing_child_values")
    end

    it "rejects dependency rules missing operator" do
      payload = {
        custom_field: {
          name: "rule field",
          type: "IssueCustomField",
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          possible_values: ["A"],
          dependency_rules: [{ value: "A", child_values: ["B"] }]
        }
      }

      expect {
        post "/depending_custom_fields.json", params: payload
      }.not_to change { CustomField.count }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"]).to have_key("dependency_rules")
      expect(body["errors"]["dependency_rules"]["0"].first).to include("code" => "missing_operator")
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
        field.update_column(:dependency_rules, '[{"operator":"equals","value":"A","child_values":["B"]}]')
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
      expect(cf["parent_field_type"]).to be_nil
      expect(cf["parent_field_key"]).to be_nil
      expect(cf["value_dependencies"]).to eq({ "1" => ["A"] })
      expect(cf["default_value_dependencies"]).to eq({ "1" => "A" })
      expect(cf["dependency_rules"]).to eq(
        [{ "operator" => "equals", "value" => "A", "child_values" => ["B"] }]
      )
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
      expect(cf["dependency_rules"]).to eq([])
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
end
