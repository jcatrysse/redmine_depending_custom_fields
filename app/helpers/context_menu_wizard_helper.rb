module ContextMenuWizardHelper
  def intersect_allowed_values(cf, issues)
    issues.inject(nil) do |memo, issue|
      vals = cf.possible_values_options(issue).map(&:last)
      memo ? (memo & vals) : vals
    end
  end

  def render_custom_field(cf, issues)
    html = custom_field_tag_for_bulk_edit('issue', cf, issues, cf.default_value)
    html.sub(/<select/, "<select data-field-id='#{cf.id}'").html_safe
  end
end
