module ContextMenuWizardHelper
  def render_custom_field(cf, issues)
    html = custom_field_tag_for_bulk_edit('issue', cf, issues, cf.default_value)
    html.sub(/<select/, "<select data-field-id='#{cf.id}'").html_safe
  end
end
