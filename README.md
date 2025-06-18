# Redmine Depending Custom Fields

This plugin provides additional custom field formats for Redmine that can be toggled via the plugin settings. Version `0.0.1` introduces an *Extended user* field format which behaves the same as the built‑in user format.

## Installation

1. Copy this plugin directory into `plugins` of your Redmine installation.
2. Run `bundle install` if required and migrate plugins with:
   `bundle exec rake redmine:plugins`.
3. Restart Redmine.

The plugin can be configured in *Administration → Plugins*.

## Compatibility

The plugin is tested with Redmine **5.1** and **6.x**.

## Development

Tests can be run using:

```bash
bundle exec rake test
```

## License

This plugin is released under the GNU GPL v3.
