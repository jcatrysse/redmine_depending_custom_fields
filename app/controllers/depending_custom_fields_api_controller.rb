class DependingCustomFieldsApiController < ApplicationController
  before_action :require_admin
  before_action :find_custom_field, only: [:show, :update, :destroy]

  accept_api_auth :index, :show, :create, :update, :destroy if respond_to?(:accept_api_auth)

  def index
    records = CustomField
                .where(field_format: field_formats)
                .to_a

    %i[enumerations trackers projects roles].each do |assoc|
      with_assoc = records.select { |cf| cf.class.reflect_on_association(assoc) }
      next unless with_assoc.any?

      if ActiveRecord::VERSION::MAJOR >= 7
        ActiveRecord::Associations::Preloader.new(
          records: with_assoc,
          associations: assoc
        ).call
      else
        @preloader ||= ActiveRecord::Associations::Preloader.new
        @preloader.preload(with_assoc, assoc)
      end
    end

    render json: records.map { |cf| format_custom_field(cf) }
  end

  def show
    render json: format_custom_field(@custom_field)
  end

  def create
    klass = custom_field_class
    if klass == CustomField && params.dig(:custom_field, :type).present? && params.dig(:custom_field, :type) != 'CustomField'
      return render json: { errors: ['Invalid custom field type'] }, status: :unprocessable_entity
    end

    @custom_field = klass.new(permitted_params.except(:enumerations, :type))
    dependency_errors = dependency_rules_errors
    if dependency_errors.any?
      return render json: { errors: { dependency_rules: dependency_errors } }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      unless @custom_field.save
        raise ActiveRecord::Rollback
      end

      unless assign_enumerations(@custom_field)
        raise ActiveRecord::Rollback
      end
    end

    if @custom_field.persisted? && @custom_field.errors.empty?
      render json: format_custom_field(@custom_field), status: :created
    else
      render json: { errors: @custom_field.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    dependency_errors = dependency_rules_errors
    if dependency_errors.any?
      return render json: { errors: { dependency_rules: dependency_errors } }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      unless @custom_field.update(permitted_params.except(:enumerations, :type))
        raise ActiveRecord::Rollback
      end

      unless assign_enumerations(@custom_field)
        raise ActiveRecord::Rollback
      end
    end

    if @custom_field.errors.empty?
      render json: format_custom_field(@custom_field)
    else
      render json: { errors: @custom_field.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @custom_field.destroy
    head :no_content
  end

  private

  def field_formats
    ['list', 'enumeration',
     RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
     RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION]
  end

  LIST_CLASS_WHITELIST = %w[
    IssueCustomField
    TimeEntryCustomField
    ProjectCustomField
    VersionCustomField
    UserCustomField
    GroupCustomField
    DocumentCategoryCustomField
    TimeEntryActivityCustomField
  ].freeze

  ENUM_CLASS_WHITELIST = %w[
    IssueCustomField
    TimeEntryCustomField
    ProjectCustomField
    VersionCustomField
    DocumentCategoryCustomField
    TimeEntryActivityCustomField
  ].freeze

  CUSTOM_FIELD_CLASS_MAP = (
    LIST_CLASS_WHITELIST + ENUM_CLASS_WHITELIST
  ).uniq.index_with { |name| Object.const_get(name) }.freeze

  def custom_field_class
    klass  = params.dig(:custom_field, :type)
    format = params.dig(:custom_field, :field_format)

    allowed = case format
              when 'enumeration', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
                ENUM_CLASS_WHITELIST
              else
                LIST_CLASS_WHITELIST
              end

    return CustomField if klass.blank? || !allowed.include?(klass)

    CUSTOM_FIELD_CLASS_MAP.fetch(klass, CustomField)
  end

  def permitted_params
    params.require(:custom_field).permit(
      :name, :description, :type, :field_format,
      :is_required, :is_filter, :searchable, :visible,
      :multiple, :default_value, :url_pattern,
      :edit_tag_style, :is_for_all,
      :parent_custom_field_id,
      :parent_field_type,
      :parent_field_key,
      :dependency_rules,
      :hide_when_disabled,
      :exclude_admins, :only_project_members, :show_active, :show_registered, :show_locked,
      possible_values: [],
      value_dependencies: {},
      default_value_dependencies: {},
      dependency_rules: [:operator, :value, :value_to, { child_values: [] }],
      enumerations: [:id, :name, :position, :_destroy, :active],
      tracker_ids: [], project_ids: [], role_ids: [], group_ids: []
    )
  end

  def find_custom_field
    @custom_field = CustomField.find_by(id: params[:id])
    return if @custom_field

    respond_to do |format|
      format.json do
        render json: { errors: ['Custom field not found'] }, status: :not_found
      end
      format.any { head :not_found }
    end
  end

  BOOLEAN_TYPE = ActiveModel::Type::Boolean.new
  private_constant :BOOLEAN_TYPE

  def cast_boolean(value)
    BOOLEAN_TYPE.cast(value) ? true : false
  end

  def format_custom_field(cf)
    enums = if cf.class.reflect_on_association(:enumerations)
              cf.enumerations.to_a
            end
    trackers = if cf.class.reflect_on_association(:trackers)
                 cf.trackers.to_a
               else
                 []
               end
    projects = if cf.class.reflect_on_association(:projects)
                 cf.projects.to_a
               else
                 []
               end
    roles = if cf.class.reflect_on_association(:roles)
              cf.roles.to_a
            else
              []
            end

    list_formats = ['list', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST]
    enum_formats = ['enumeration', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION]
    depending_formats = [
      RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
      RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
    ]

    payload = {
      id: cf.id,
      name: cf.name,
      description: cf.description,
      type: cf.type,
      field_format: cf.field_format,
      is_required: cf.is_required,
      is_filter: cf.is_filter,
      searchable: cf.searchable,
      visible: cf.visible,
      multiple: cf.multiple,
      default_value: cf.default_value,
      url_pattern: cf.respond_to?(:url_pattern) ? cf.url_pattern : nil,
      edit_tag_style: cf.respond_to?(:edit_tag_style) ? cf.edit_tag_style : nil,
      is_for_all: cf.is_for_all,
      only_project_members: cf.respond_to?(:only_project_members) ? cast_boolean(cf.only_project_members) : nil,
      trackers: trackers.map { |t| { id: t.id, name: t.name } },
      projects: projects.map { |p| { id: p.id, name: p.name } },
      roles: roles.map { |r| { id: r.id, name: r.name } }
    }

    if list_formats.include?(cf.field_format)
      payload[:possible_values] = cf.possible_values || []
    end

    if enum_formats.include?(cf.field_format)
      payload[:enumerations] = (enums || []).map do |e|
        { id: e.id, name: e.name, position: e.position, active: e.active }
      end
    end

    if depending_formats.include?(cf.field_format)
      payload[:parent_custom_field_id] = cf.parent_custom_field_id
      payload[:parent_field_type] = cf.parent_field_type
      payload[:parent_field_key] = cf.parent_field_key
      payload[:value_dependencies] = cf.value_dependencies || {}
      payload[:default_value_dependencies] = cf.default_value_dependencies || {}
      payload[:dependency_rules] = normalize_dependency_rules(cf.dependency_rules)
      payload[:hide_when_disabled] = cast_boolean(cf.hide_when_disabled)
    end

    if cf.field_format == RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER
      payload[:group_ids] = Array(cf.group_ids).reject(&:blank?).map(&:to_i)
      payload[:exclude_admins] = cast_boolean(cf.exclude_admins)
      payload[:show_active] = cast_boolean(cf.show_active)
      payload[:show_registered] = cast_boolean(cf.show_registered)
      payload[:show_locked] = cast_boolean(cf.show_locked)
    end

    payload
  end

  def assign_enumerations(custom_field)
    enums = permitted_params[:enumerations]
    return true unless enums

    existing_enumerations = custom_field.enumerations.index_by(&:id)
    to_destroy = []

    enums.each do |e_params|
      attrs = e_params.to_h.symbolize_keys
      destroy_flag = cast_boolean(attrs[:_destroy])

      if attrs[:id].present?
        enumeration = existing_enumerations[attrs[:id].to_i]
        next unless enumeration

        if destroy_flag
          to_destroy << enumeration
          next
        end

        enumeration.assign_attributes(attrs.except(:id, :_destroy))
        next if enumeration.save

        collect_child_errors(custom_field, enumeration)
        return false
      else
        next if destroy_flag

        enumeration = custom_field.enumerations.build(attrs.except(:_destroy))
        next if enumeration.save

        collect_child_errors(custom_field, enumeration)
        return false
      end
    end

    to_destroy.each(&:destroy)
    true
  end

  def dependency_rules_errors
    rules = permitted_params[:dependency_rules]
    return [] if rules.nil?

    parsed, error = RedmineDependingCustomFields::Sanitizer.parse_dependency_rules(rules)
    return { base: [{ code: 'invalid_json', message: I18n.t(:text_dependency_rules_invalid_json) }] } if error

    schema_errors = RedmineDependingCustomFields::Sanitizer.rule_schema_errors(parsed)
    if schema_errors.any?
      return schema_errors.group_by { |schema| schema[:index] }.transform_values do |items|
        items.map do |schema|
          {
            code: schema[:code],
            message: I18n.t(:text_dependency_rules_invalid_rule_index, index: schema[:index] + 1)
          }
        end
      end
    end

    []
  end

  def normalize_dependency_rules(value)
    return value if value.is_a?(Array)
    return [] if value.nil?

    if value.is_a?(String)
      JSON.parse(value)
    else
      []
    end
  rescue JSON::ParserError
    []
  end

  def collect_child_errors(parent, child)
    child.errors.full_messages.each do |message|
      parent.errors.add(:base, message)
    end
  end
end
