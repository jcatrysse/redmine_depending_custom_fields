module ContextMenuWizardHelper
  # Core's bulk tag of +cf+ for the selected +issues+ (the format's
  # bulk_edit_tag adds the data-dcf-* bulk attributes). The value is nil, so
  # every wizard field, the root included, opens on '(no change)' (UD-11).
  def render_custom_field(cf, issues)
    custom_field_tag_for_bulk_edit('issue', cf, issues, nil)
  end
end
