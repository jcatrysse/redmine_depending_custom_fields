class DependableCustomFieldsApiController < ApplicationController
  before_action :find_custom_field, only: [:show, :update, :destroy]

  accept_api_auth :index, :show, :create, :update, :destroy if respond_to?(:accept_api_auth)

  def index
    fields = CustomField.where(field_format: field_formats)
    render json: fields.map { |cf| format_custom_field(cf) }
  end

  def show
    render json: format_custom_field(@custom_field)
  end

  def create
    @custom_field = custom_field_class.new(permitted_params.except(:enumerations))
    assign_enumerations(@custom_field)
    if @custom_field.save
      render json: format_custom_field(@custom_field), status: :created
    else
      render json: { errors: @custom_field.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    @custom_field.assign_attributes(permitted_params.except(:enumerations))
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
     RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_LIST,
     RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_ENUMERATION]
  end

  def custom_field_class
    klass = params[:custom_field] && params[:custom_field][:type]
    klass.present? ? klass.constantize : CustomField
  rescue NameError
    CustomField
  end

  def permitted_params
    params.require(:custom_field).permit(
      :name, :description, :type, :field_format,
      :is_required, :is_filter, :searchable, :visible,
      :multiple, :default_value, :url_pattern,
      :edit_tag_style, :is_for_all,
      :parent_custom_field_id,
      possible_values: [],
      value_dependencies: {},
      enumerations: [:id, :name, :position, :_destroy, :active],
      tracker_ids: [], project_ids: [], role_ids: []
    )
  end

  def find_custom_field
    @custom_field = CustomField.find(params[:id])
  end

  def format_custom_field(cf)
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
      enumerations: cf.respond_to?(:enumerations) ? cf.enumerations.map { |e| { id: e.id, name: e.name, position: e.position } } : nil,
      trackers: cf.respond_to?(:trackers) ? cf.trackers.map { |t| { id: t.id, name: t.name } } : [],
      projects: cf.respond_to?(:projects) ? cf.projects.map { |p| { id: p.id, name: p.name } } : [],
      roles: cf.respond_to?(:roles) ? cf.roles.map { |r| { id: r.id, name: r.name } } : [],
      parent_custom_field_id: cf.respond_to?(:parent_custom_field_id) ? cf.parent_custom_field_id : nil,
      value_dependencies: cf.respond_to?(:value_dependencies) ? cf.value_dependencies : nil
    }
  end

  def assign_enumerations(custom_field)
    enums = permitted_params[:enumerations]
    return unless enums

    enums.each do |e_params|
      attrs = e_params.to_h.symbolize_keys

      if attrs[:id].present?
        enumeration = custom_field.enumerations.find_by(id: attrs[:id])
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
