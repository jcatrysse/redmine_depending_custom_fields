require_relative '../rails_helper'

RSpec.describe "DependingCustomFields API", type: :request do
  fixtures :users # admin is id:1 in Redmine fixtures

  before do
    allow(User).to receive(:current).and_return(User.find(1))
  end

  FIELD_FORMATS = [
    'list',
    'enumeration',
    RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
    RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
  ].freeze

  FIELD_TYPES = (DependingCustomFieldsApiController::CUSTOM_FIELD_CLASS_MAP.keys + ['CustomField', nil]).freeze

  def boolean
    satisfy { |v| v == true || v == false }
  end

  def expect_field_structure(cf, name: nil, field_format: nil, type: nil)
    expect(cf).to include(
                    "id" => kind_of(Integer),
                    "name" => name || kind_of(String),
                    "type" => type || satisfy { |t| FIELD_TYPES.include?(t) },
                    "field_format" => field_format || satisfy { |v| FIELD_FORMATS.include?(v) },
                    "is_required" => boolean,
                    "is_filter" => boolean,
                    "searchable" => boolean,
                    "visible" => boolean,
                    "multiple" => boolean,
                    "default_value" => anything,
                    "url_pattern" => anything,
                    "edit_tag_style" => anything,
                    "is_for_all" => boolean,
                    "possible_values" => kind_of(Array),
                    "enumerations" => be_nil.or(be_kind_of(Array)),
                    "trackers" => kind_of(Array),
                    "projects" => kind_of(Array),
                    "roles" => kind_of(Array),
                    "parent_custom_field_id" => be_nil.or(be_kind_of(Integer)),
                    "value_dependencies" => be_nil.or(be_kind_of(Hash)),
                    "default_value_dependencies" => be_nil.or(be_kind_of(Hash)),
                    "hide_when_disabled" => boolean
                  )
  end

  describe "GET /depending_custom_fields" do
    it "returns 200 and an array of fields" do
      get "/depending_custom_fields.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
      body.each { |cf| expect_field_structure(cf) }
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
      expect_field_structure(
        cf,
        name: "spec field",
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        type: "IssueCustomField"
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
