module ContextMenuWizardHelper
  def intersect_allowed_values(cf, issues)
    issues.inject(nil) do |memo, issue|
      options = cf.possible_values_options(issue)
      vals = options.reject { |o| o.is_a?(Array) && o[2].is_a?(Hash) && o[2][:class] == 'option-group' }.map(&:last)
      memo ? (memo & vals) : vals
    end
  end

  def render_custom_field(cf, issues)
    html = custom_field_tag_for_bulk_edit('issue', cf, issues, cf.default_value)
    html.gsub(/<select(?![^>]*\bdata-field-id=)/, "<select data-field-id='#{cf.id}'").html_safe
  end
end
