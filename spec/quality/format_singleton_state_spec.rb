# frozen_string_literal: true

require_relative '../rails_helper'
require 'ripper'

# Format objects are process-wide singletons shared by every request and
# every issue (core Redmine::FieldFormat.add registers klass.instance), and
# DependencyRules is module_function. Neither may keep state: per-record
# caching goes through CustomFieldPatch#dcf_memo only (server design section
# 3, SP-16, WP-06).
RSpec.describe 'Format singleton state' do
  fixtures :users

  lib_dir = File.expand_path('../../lib/redmine_depending_custom_fields', __dir__)
  scanned = %w[depending_format_methods.rb depending_list_format.rb depending_enumeration_format.rb
               dependency_rules.rb extended_user_format.rb].map { |name| File.join(lib_dir, name) }

  # Names of the instance, class and global variables the source assigns
  # (=, op-assign, multiple assignment, rescue =>, inside blocks), plus the
  # calls that set state by name. Comments, strings and heredocs do not count,
  # reads and comparisons neither. nil when the source does not parse.
  def state_writes(source)
    sexp = Ripper.sexp(source)
    return nil if sexp.nil?

    found = []
    walk = lambda do |node|
      next unless node.is_a?(Array)

      if node[0] == :var_field && node[1].is_a?(Array) && [:@ivar, :@cvar, :@gvar].include?(node[1][0])
        found << node[1][1]
      end
      node.each { |child| walk.call(child) }
    end
    walk.call(sexp)
    setters = %w[instance_variable_set class_variable_set attr_accessor attr_writer]
    Ripper.lex(source).each { |(_pos, type, token)| found << token if type == :on_ident && setters.include?(token) }
    found
  end

  describe 'source scan' do
    it 'detects every assignment form and ignores comments, strings, heredocs and reads' do
      snippet = <<~SNIPPET
        # @c1 = 1 in a comment
        x = '@s1 = 1'
        y = <<~TEXT
          @h1 = 1
        TEXT
        z = %q(@q1 = 1)
        @r1 == x
        w = @r2
        def m
          @a = 1
          @b ||= {}
          @c &&= 2
          @d += 1
          @e, @f = 1, 2
          [1].each { @g = 3 }
          begin
          rescue StandardError => @err
          end
          @@k = 1
          $glob = 1
        end
        instance_variable_set(:@m, 1)
      SNIPPET

      expect(state_writes(snippet))
        .to match_array(%w[@a @b @c @d @e @f @g @err @@k $glob instance_variable_set])
      expect(state_writes('def broken(')).to be_nil
    end

    scanned.each do |path|
      it "#{File.basename(path)} assigns no instance, class or global variable" do
        source = File.read(path, encoding: 'UTF-8')
        expect(state_writes(source)).to eq([])
        expect(source).not_to match(/Thread\.current|CurrentAttributes|Rails\.cache\.(?:fetch|read|write)/)
      end
    end
  end

  describe 'runtime' do
    include DcfFormatCharacterization

    let(:project) { dcf_create_project }

    # Core RecordList#target_class memoizes @target_class on the enumeration
    # format object; nothing else may appear on a format object.
    core_ivars = [:@target_class]

    def run_every_method(fmt, kind)
      parent, child = build_kit(kind)
      issue = kit_issue(project, parent => 'A', child => 'a1')
      fmt.possible_values_options(child, issue)
      fmt.possible_values_options(child, nil)
      fmt.possible_values_options(child, [issue])
      cfv = issue.custom_field_values.detect { |v| v.custom_field_id == child.id }
      fmt.validate_custom_value(cfv)
      fmt.validate_custom_field(child)
      fmt.value_from_keyword(child, 'a1', issue)
      fmt.storage_preview(child, child.format_store)
      fmt.normalized_store_pairs(child)
      fmt.before_custom_field_save(child)
      fmt.after_custom_field_save(child)
      fmt.query_filter_values(child, IssueQuery.new(name: '_', project: project))
    end

    # Absolute checks, independent of what earlier examples of the process
    # ran: a fresh object of each format class (Singleton makes new private,
    # it does not remove it), the class objects against their core class
    # (both carry the Singleton bookkeeping), and the two modules.
    [[:list, RedmineDependingCustomFields::DependingListFormat, Redmine::FieldFormat::ListFormat],
     [:enumeration, RedmineDependingCustomFields::DependingEnumerationFormat,
      Redmine::FieldFormat::EnumerationFormat]].each do |kind, klass, core|
      it "keeps no state on a fresh #{kind} format object or its class when every method runs" do
        fmt = klass.send(:new)
        run_every_method(fmt, kind)

        expect(fmt.instance_variables - core_ivars).to eq([])
        expect(klass.instance_variables - core.instance_variables).to eq([])
      end
    end

    it 'keeps no state on the shared format singletons and the rules modules' do
      run_every_method(RedmineDependingCustomFields::DependingListFormat.instance, :list)
      run_every_method(RedmineDependingCustomFields::DependingEnumerationFormat.instance, :enumeration)

      expect(RedmineDependingCustomFields::DependingListFormat.instance.instance_variables - core_ivars).to eq([])
      expect(RedmineDependingCustomFields::DependingEnumerationFormat.instance.instance_variables - core_ivars).to eq([])
      expect(RedmineDependingCustomFields::DependingFormatMethods.instance_variables).to eq([])
      expect(RedmineDependingCustomFields::DependencyRules.instance_variables).to eq([])
    end

    [:list, :enumeration].each do |kind|
      it "gives one #{kind} child instance a result per issue, in either order" do
        parent, child = build_kit(kind)
        fmt = child.format
        on_a = kit_issue(project, parent => 'A')
        on_b = kit_issue(project, parent => 'B')
        hidden = DcfFormatCharacterization::HIDDEN
        for_a = [pair(child, 'a1'), pair(child, 'a2'), pair(child, 'b1', hidden)]
        for_b = [pair(child, 'a1', hidden), pair(child, 'a2', hidden), pair(child, 'b1')]

        expect(fmt.possible_values_options(child, on_a)).to eq(for_a)
        expect(fmt.possible_values_options(child, on_b)).to eq(for_b)
        expect(fmt.possible_values_options(child, on_a)).to eq(for_a)
      end
    end
  end

  # Two requests in a row on one child whose parent pointer changes in
  # between: the second request must see the new parent. Asserts the response
  # (redirect or edit form with the child's error) and the stored value only,
  # so the example holds through WP-08, WP-09 and WP-10.
  describe 'sequential requests', type: :request do
    include DcfFormatCharacterization

    before { allow(User).to receive(:current).and_return(dcf_admin) }

    [:list, :enumeration].each do |kind|
      context "with a depending #{kind} field" do
        let(:project) { dcf_create_project }
        let(:first_parent) { kind == :list ? dcf_list_field(values: %w[A]) : dcf_enum_field(names: %w[A]) }
        let(:second_parent) { kind == :list ? dcf_list_field(values: %w[B]) : dcf_enum_field(names: %w[B]) }
        let(:child) do
          field = if kind == :list
                    dcf_list_field(format: 'depending_list', values: %w[c1 c2], parent: first_parent)
                  else
                    dcf_enum_field(format: 'depending_enumeration', names: %w[c1 c2], parent: first_parent)
                  end
          dcf_set_dependencies(field, value_dependencies: { kit_key(first_parent, 'A') => [kit_key(field, 'c1')],
                                                            kit_key(second_parent, 'B') => [kit_key(field, 'c2')] })
        end
        let(:issue) { kit_issue(project, first_parent => 'A', second_parent => 'B', child => []) }

        # show_exceptions renders an exception as a 500 page, so the response
        # tells a validation rejection (edit form again, 200, with the child's
        # error) from a crash; an accepted update redirects.
        def expect_outcome(outcome)
          if outcome == :accepted
            expect(response).to have_http_status(302)
          else
            expect(response).to have_http_status(200)
            expect(Nokogiri::HTML(response.body).css('#errorExplanation').text).to include(child.name)
          end
        end

        def put_child(name, outcome:)
          put "/issues/#{issue.id}", params: { issue: { custom_field_values: { child.id.to_s => kit_key(child, name) } } }
          expect_outcome(outcome)
          Issue.find(issue.id).custom_field_value(child).to_s
        end

        def point_child_to(parent)
          field = CustomField.find(child.id)
          field.parent_custom_field_id = parent.id
          field.save!
        end

        it 'rejects, then accepts after the parent changed' do
          expect(put_child('c2', outcome: :rejected)).to eq('')
          point_child_to(second_parent)
          expect(put_child('c2', outcome: :accepted)).to eq(kit_key(child, 'c2'))
        end

        it 'accepts, then rejects after the parent changed' do
          point_child_to(second_parent)
          expect(put_child('c2', outcome: :accepted)).to eq(kit_key(child, 'c2'))
          put "/issues/#{issue.id}", params: { issue: { custom_field_values: { child.id.to_s => '' } } }
          expect_outcome(:accepted)
          expect(Issue.find(issue.id).custom_field_value(child).to_s).to eq('')
          point_child_to(first_parent)
          expect(put_child('c2', outcome: :rejected)).to eq('')
        end
      end
    end
  end
end
