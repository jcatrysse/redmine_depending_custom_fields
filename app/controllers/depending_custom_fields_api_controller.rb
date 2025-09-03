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
    assign_enumerations(@custom_field)
    if @custom_field.save
      render json: format_custom_field(@custom_field), status: :created
    else
      render json: { errors: @custom_field.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    @custom_field.assign_attributes(permitted_params.except(:enumerations, :type))
    assign_enumerations(@custom_field)

    if @custom_field.save
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
      :hide_when_disabled,
      possible_values: [],
      value_dependencies: {},
      default_value_dependencies: {},
      enumerations: [:id, :name, :position, :_destroy, :active],
      tracker_ids: [], project_ids: [], role_ids: []
    )
  end

  def find_custom_field
    @custom_field = CustomField.find(params[:id])
  end

  def format_custom_field(cf)
    enums    = cf.class.reflect_on_association(:enumerations) ? cf.association(:enumerations).target : nil
    trackers = cf.class.reflect_on_association(:trackers) ? cf.association(:trackers).target : []
    projects = cf.class.reflect_on_association(:projects) ? cf.association(:projects).target : []
    roles    = cf.class.reflect_on_association(:roles) ? cf.association(:roles).target : []

    {
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
      possible_values: cf.possible_values,
      enumerations: enums&.map { |e| { id: e.id, name: e.name, position: e.position } },
      trackers: trackers.map { |t| { id: t.id, name: t.name } },
      projects: projects.map { |p| { id: p.id, name: p.name } },
      roles: roles.map { |r| { id: r.id, name: r.name } },
      parent_custom_field_id: cf.respond_to?(:parent_custom_field_id) ? cf.parent_custom_field_id : nil,
      value_dependencies: cf.respond_to?(:value_dependencies) ? cf.value_dependencies : nil,
      default_value_dependencies: cf.respond_to?(:default_value_dependencies) ? cf.default_value_dependencies : nil,
      hide_when_disabled: cf.respond_to?(:hide_when_disabled) ? !!cf.hide_when_disabled : false
    }
  end

  def assign_enumerations(custom_field)
    enums = permitted_params[:enumerations]
    return unless enums

    existing_enumerations = custom_field.enumerations.index_by(&:id)

    enums.each do |e_params|
      attrs = e_params.to_h.symbolize_keys

      if attrs[:id].present?
        enumeration = existing_enumerations[attrs[:id].to_i]
        if attrs[:_destroy]
          enumeration.destroy if enumeration
          next
        end
        enumeration.update(attrs.except(:id, :_destroy)) if enumeration
      else
        custom_field.enumerations.build(attrs.except(:_destroy))
      end
    end
  end
end
