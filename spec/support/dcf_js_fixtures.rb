# frozen_string_literal: true

require 'fileutils'
require 'nokogiri'

# WP-16: the one fixture mechanism for server-rendered markup that the jsdom
# suites read (server design 2.5, quality 5.5). Records whose ids reach the
# markup get ids from the fixed ranges of dcf_fixture_record (WP-02); the
# normalizer scrubs tokens, state hashes, asset digests and timestamps; the
# guard fails, naming the position, on any id-bearing number outside the
# ranges (a leaked sequence id); dcf_js_fixture writes the file when
# DCF_WRITE_JS_FIXTURES=1 (into DCF_JS_FIXTURE_DIR, default the plugin's
# test/js/fixtures) and compares otherwise. Generic per group: markup
# (WP-16), head (WP-18) and editor (WP-24) use the same helpers. Specs
# require this file and include the module (rails_helper does not load it).
module DcfJsFixtures
  # Fixtures are written on this version; another version writes
  # <scenario>.redmine-<x.y>.html only when its output differs.
  BASE_VERSION = '7.0'
  RANGE_WIDTH = 99_999
  TOKEN = '{{TOKEN}}'
  STATE_HASH = '{{STATE_HASH}}'
  VOID_ELEMENTS = %w[area base br col embed hr img input link meta source track wbr].freeze
  # Kinds of the ranges in DcfConfigHelpers::DCF_FIXTURE_ID_BASES.
  CF = 'CustomField'
  ENUMERATION = 'CustomFieldEnumeration'
  ISSUE = 'Issue'
  ANY = :any
  # Attributes that hold one id, and the kind of that id.
  ID_ATTRIBUTES = {
    'data-dcf-field' => CF, 'data-dcf-parent' => CF, 'data-dcf-locked-parent' => CF, 'data-parent-id' => CF,
    'data-field-id' => CF, 'data-dcf-editor-field-id' => CF, 'data-dcf-editor-parent-id' => CF,
    'data-dcf-wizard-field' => CF
  }.freeze
  # Attributes whose JSON may hold enumeration ids (numbers or digit strings).
  JSON_ATTRIBUTES = %w[data-dcf-map data-dcf-defaults data-dcf-parent-values data-dcf-stored
                       data-dcf-locked-stored data-dcf-locked-allowed-by].freeze
  PATH_KINDS = { 'issues' => ISSUE, 'custom_fields' => CF, 'fields' => CF }.freeze

  class LeakedId < StandardError; end

  def dcf_js_fixture_dir
    ENV['DCF_JS_FIXTURE_DIR'].presence || File.expand_path('../../test/js/fixtures', __dir__)
  end

  def dcf_js_write_fixtures?
    ENV['DCF_WRITE_JS_FIXTURES'] == '1'
  end

  def dcf_redmine_version
    "#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}"
  end

  def dcf_fixture_range(kind)
    base = DcfConfigHelpers::DCF_FIXTURE_ID_BASES.fetch(kind)
    base..(base + RANGE_WIDTH - 1)
  end

  def dcf_in_fixture_range?(number, kind)
    kinds = kind == ANY ? DcfConfigHelpers::DCF_FIXTURE_ID_BASES.keys : [kind]
    kinds.any? { |k| dcf_fixture_range(k).cover?(number) }
  end

  # Parses an HTML fragment as browsers and jsdom do (template contents
  # included).
  def dcf_parse_fragment(html)
    Nokogiri::HTML5.fragment(html)
  end

  # A fixed serialization, independent of the Nokogiri version: attributes
  # in source order, values escaped (& " < >), text escaped (& < >),
  # comments dropped, void elements without a closing tag.
  def dcf_serialize(node)
    case node
    when Nokogiri::XML::Text
      node.content.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
    when Nokogiri::XML::Element
      attributes = node.attribute_nodes.map { |a| " #{a.name}=\"#{dcf_escape_attribute(a.value)}\"" }.join
      return "<#{node.name}#{attributes}>" if VOID_ELEMENTS.include?(node.name)

      "<#{node.name}#{attributes}>#{node.children.map { |c| dcf_serialize(c) }.join}</#{node.name}>"
    when Nokogiri::XML::DocumentFragment, Nokogiri::XML::Document
      node.children.map { |c| dcf_serialize(c) }.join
    else
      ''
    end
  end

  def dcf_escape_attribute(value)
    value.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  # Rewrites only known volatile positions: the authenticity token input and
  # the CSRF meta, state hashes, and the timestamp and digest of asset src
  # and href attributes (dcf_js_asset_url; script, link, img and, WP-24, svg
  # use). Values, labels, option values and data-dcf JSON are never touched.
  # Returns the serialized fragment.
  def dcf_js_normalize(html)
    fragment = html.is_a?(String) ? dcf_parse_fragment(html) : html
    fragment.css('input[name="authenticity_token"]').each { |input| input['value'] = TOKEN }
    fragment.css('meta[name="csrf-token"]').each { |meta| meta['content'] = TOKEN }
    fragment.css('meta[name="csrf-param"]').each { |meta| meta['content'] = TOKEN }
    fragment.css('input').each { |input| input['value'] = STATE_HASH if input['name'].to_s.include?('state_hash') }
    fragment.traverse do |node|
      next unless node.element?

      node.attribute_nodes.each do |attr|
        attr.value = STATE_HASH if attr.name.match?(/state[-_]hash/)
      end
      next unless %w[script link img use].include?(node.name)

      %w[src href].each do |name|
        next unless node[name]

        node[name] = dcf_js_asset_url(node[name])
      end
      dcf_js_order_link_attributes(node) if node.name == 'link'
    end
    dcf_serialize(fragment)
  end

  # WP-18: rel, href, then the other attributes by name (Rails 6.1 writes
  # media before href, Rails 7 after it).
  def dcf_js_order_link_attributes(node)
    pairs = node.attribute_nodes.map { |attr| [attr.name, attr.value] }
    order = %w[rel href]
    sorted = pairs.sort_by { |name, _| [order.index(name) || order.size, name] }
    return if sorted == pairs

    pairs.map(&:first).each { |name| node.remove_attribute(name) }
    sorted.each { |name, value| node[name] = value }
  end

  # WP-18 (head fixtures): an asset URL without its digest (64 hex, or the 8
  # hex of Propshaft on 6.x/7.0) and its 5.1 asset id, and a plugin asset in
  # the version-independent form /plugin_assets/<plugin>/<file> (5.1 adds
  # javascripts/ or stylesheets/, Propshaft serves it below /assets).
  # WP-24 (editor fixtures): also the href of an svg sprite use element
  # (sprite_icon, 6.0 and later), whose digest is followed by #icon--<name>.
  def dcf_js_asset_url(url)
    url = url.sub(/-(?:[0-9a-f]{64}|[0-9a-f]{8})(?=\.\w+(\?|#|\z))/, '').sub(/\?\d+\z/, '')
    url.sub(%r{\A(?:/assets)?/plugin_assets/([^/]+)/(?:javascripts/|stylesheets/)?}, '/plugin_assets/\\1/')
  end

  # Raises LeakedId, naming the node path and attribute, when a number in an
  # id-bearing position is outside its fixed range.
  def dcf_js_guard!(html)
    fragment = html.is_a?(String) ? dcf_parse_fragment(html) : html
    problems = []
    check = lambda do |node, where, number, kind|
      next if dcf_in_fixture_range?(number, kind)

      problems << "#{number} at #{dcf_node_position(node)} #{where} (expected the #{kind == ANY ? 'any' : kind} range)"
    end
    fragment.traverse do |node|
      next unless node.element?

      dcf_guard_element(node, check)
    end
    raise LeakedId, "leaked sequence ids: #{problems.join('; ')}" if problems.any?

    true
  end

  # The element chain of +node+ inside its fragment, ids included.
  def dcf_node_position(node)
    chain = node.ancestors.select(&:element?).reverse + [node]
    chain.map { |n| n['id'] ? "#{n.name}##{n['id']}" : n.name }.join(' > ')
  end

  def dcf_guard_element(node, check)
    enumeration = dcf_enumeration_control?(node)
    node.attribute_nodes.each do |attr|
      name = attr.name
      value = attr.value.to_s
      value.scan(/\[custom_field_values\]\[(\d+)\]/) { |(n)| check.call(node, "@#{name}", n.to_i, CF) }
      value.scan(/custom_field_values_(\d+)/) { |(n)| check.call(node, "@#{name}", n.to_i, CF) } if %w[id for].include?(name)
      value.scan(/(?:\A|\s)cf_(\d+)(?=\s|\z)/) { |(n)| check.call(node, "@#{name}", n.to_i, CF) } if name == 'class'
      value.scan(%r{/(issues|custom_fields|fields)/(\d+)}) { |(path, n)| check.call(node, "@#{name}", n.to_i, PATH_KINDS[path]) }
      value.scan(/cf-wizard-(\d+)/) { |(n)| check.call(node, "@#{name}", n.to_i, CF) }
      check.call(node, "@#{name}", value.to_i, ID_ATTRIBUTES[name]) if ID_ATTRIBUTES.key?(name) && value.match?(/\A\d+\z/)
      if name == 'data-issue-ids'
        value.split(',').each { |n| check.call(node, "@#{name}", n.to_i, ISSUE) }
      end
      dcf_guard_json(node, name, value, check) if JSON_ATTRIBUTES.include?(name)
    end
    dcf_guard_values(node, check, enumeration)
  end

  def dcf_guard_values(node, check, enumeration)
    if node.name == 'input' && %w[ids[] issue_ids].include?(node['name'])
      node['value'].to_s.split(',').each { |n| check.call(node, '@value', n.to_i, ISSUE) }
    end
    return unless enumeration

    controls = node.name == 'option' ? [node] : []
    controls << node if node.name == 'input' && %w[radio checkbox].include?(node['type'])
    controls.each do |control|
      value = control['value'].to_s
      check.call(control, '@value', value.to_i, ENUMERATION) if value.match?(/\A\d+\z/)
    end
  end

  # An option or a radio/checkbox of an enumeration field (core css class
  # enumeration_cf or depending_enumeration_cf on the select or group).
  def dcf_enumeration_control?(node)
    return false unless node.name == 'option' || (node.name == 'input' && %w[radio checkbox].include?(node['type']))

    control = node.ancestors.detect { |a| a.element? && %w[select span].include?(a.name) && a['class'].to_s.include?('enumeration_cf') }
    !control.nil?
  end

  def dcf_guard_json(node, name, value, check)
    data = JSON.parse(value)
    walk = lambda do |item|
      case item
      when Hash
        item.each do |key, child|
          check.call(node, "@#{name} key", key.to_i, ENUMERATION) if key.to_s.match?(/\A\d+\z/)
          walk.call(child)
        end
      when Array then item.each { |child| walk.call(child) }
      when Integer then check.call(node, "@#{name}", item, ENUMERATION)
      when String then check.call(node, "@#{name}", item.to_i, ENUMERATION) if item.match?(/\A\d+\z/)
      end
    end
    walk.call(data)
  rescue JSON::ParserError
    check.call(node, "@#{name} (not JSON)", -1, ENUMERATION)
  end

  def dcf_js_fixture_path(group, scenario, version = nil, ext: 'html')
    file = version ? "#{scenario}.redmine-#{version}.#{ext}" : "#{scenario}.#{ext}"
    File.join(dcf_js_fixture_dir, group, file)
  end

  # Writes or compares the normalized +html+ of +scenario+ in +group+. The
  # guard runs in both modes. In compare mode the version variant wins when
  # it exists. Returns the normalized html.
  def dcf_js_fixture(group, scenario, html)
    normalized = dcf_js_normalize(html)
    dcf_js_guard!(normalized)
    normalized = "#{normalized}\n" unless normalized.end_with?("\n")
    dcf_js_write_or_compare(group, scenario, normalized, 'html')
  end

  # Writes (DCF_WRITE_JS_FIXTURES=1) or compares +text+; in compare mode the
  # version variant wins when it exists. Returns +text+.
  def dcf_js_write_or_compare(group, scenario, text, ext)
    base = dcf_js_fixture_path(group, scenario, ext: ext)
    variant = dcf_js_fixture_path(group, scenario, dcf_redmine_version, ext: ext)
    if dcf_js_write_fixtures?
      dcf_js_write_fixture(base, variant, text)
    else
      expected_path = File.exist?(variant) ? variant : base
      raise "missing fixture #{expected_path}: run with DCF_WRITE_JS_FIXTURES=1" unless File.exist?(expected_path)

      expect(text).to eq(File.read(expected_path, encoding: 'UTF-8')), "#{expected_path} differs"
    end
    text
  end

  def dcf_js_write_fixture(base, variant, normalized)
    FileUtils.mkdir_p(File.dirname(base))
    if dcf_redmine_version == BASE_VERSION
      File.write(base, normalized)
    elsif File.exist?(base) && File.read(base, encoding: 'UTF-8') == normalized
      FileUtils.rm_f(variant)
    else
      File.write(variant, normalized)
    end
  end

  # The next render takes the same fixed ids again (dcf_fixture_record).
  def dcf_reset_fixture_ids
    @dcf_fixture_counters = nil
  end

  # Creates +count+ inert rows of every kind with a fixed range, through
  # the sequences, so later sequence ids move; nothing links them to a
  # scenario (no tracker, project, membership or is_for_all).
  def dcf_bump_sequences(count = 37)
    status = IssueStatus.create!(name: "Bump status #{SecureRandom.hex(4)}")
    tracker = Tracker.new(name: "Bump tracker #{SecureRandom.hex(4)}")
    tracker.default_status = status
    tracker.save!
    project = Project.new(name: 'Bump project', identifier: "dcf-bump-#{SecureRandom.hex(4)}")
    project.save!(validate: false)
    priority = IssuePriority.first || IssuePriority.create!(name: 'Normal')
    enum_field = IssueCustomField.create!(name: "Bump enum #{SecureRandom.hex(4)}", field_format: 'enumeration',
                                          is_for_all: false)
    count.times do |i|
      IssueStatus.create!(name: "Bump status #{SecureRandom.hex(6)}")
      bump_tracker = Tracker.new(name: "Bump tracker #{SecureRandom.hex(6)}")
      bump_tracker.default_status = status
      bump_tracker.save!
      Project.new(name: 'Bump', identifier: "dcf-bump-#{SecureRandom.hex(6)}").save!(validate: false)
      Role.create!(name: "Bump role #{SecureRandom.hex(6)}")
      User.new(login: "bump#{SecureRandom.hex(6)}", firstname: 'Bump', lastname: 'Bump',
               status: User::STATUS_ACTIVE).save!(validate: false)
      IssueCustomField.create!(name: "Bump field #{SecureRandom.hex(6)}", field_format: 'string', is_for_all: false)
      CustomFieldEnumeration.create!(custom_field_id: enum_field.id, name: "Bump #{i}", position: i + 1, active: true)
      Issue.new(project: project, tracker: tracker, subject: 'Bump', author: User.find(1), status: status,
                priority: priority).save!(validate: false)
    end
  end
end
