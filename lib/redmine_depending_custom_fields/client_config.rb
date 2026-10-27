# frozen_string_literal: true

module RedmineDependingCustomFields
  # The texts the browser runtime and the wizard script read from the head
  # meta tag (server design 2.4, frontend design 3.6, WP-18): a flat JSON
  # object of JS key => text in the current locale. I18N is the single i18n
  # map of that tag (gap 5); the frontend owns the key list. lockedRefused
  # is the warning for a parent change the server will refuse because of a
  # visible read-only dependent field (UD-37).
  #
  # module_function and stateless: the payload is built per call.
  module ClientConfig
    META_NAME = 'dcf-i18n'
    I18N = {
      'selectParent' => :text_dcf_hint_select_parent,
      'noOptions' => :text_dcf_hint_no_options,
      'noOptionsGeneric' => :text_dcf_hint_no_options_generic,
      'legacy' => :text_dcf_hint_legacy,
      'legacyLocked' => :text_dcf_hint_legacy_locked,
      'legacyGeneric' => :text_dcf_hint_legacy_generic,
      'bulkDefault' => :text_dcf_hint_bulk_default,
      'bulkCleared' => :text_dcf_hint_bulk_cleared,
      'liveMessage' => :text_dcf_live_message,
      'saveFailed' => :error_save_failed,
      'lockedRefused' => :text_dcf_hint_locked_refused
    }.freeze
    # Compared with controller.class.name; nothing is constantized.
    EDITOR_CONTROLLERS = %w[CustomFieldsController ProjectCustomFieldConfigurationController].freeze
    PLUGIN = 'redmine_depending_custom_fields'

    module_function

    def payload
      I18N.transform_values { |key| ::I18n.t(key) }
    end

    def editor_page?(controller)
      !controller.nil? && EDITOR_CONTROLLERS.include?(controller.class.name)
    end

    # The editor model, the editor script and its stylesheet, in this order
    # (the model first: the editor builds every ValueList and State with it).
    def editor_asset_tags(view)
      [view.javascript_include_tag('dcf_dependency_editor_model', plugin: PLUGIN),
       view.javascript_include_tag('dcf_dependency_editor', plugin: PLUGIN),
       view.stylesheet_link_tag('dcf_dependency_editor', plugin: PLUGIN)]
    end
  end
end
