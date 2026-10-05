# frozen_string_literal: true

require_relative '../rails_helper'
require_relative '../../.codex/lib/rubocop_ratchet'
require_relative '../../.codex/lib/compat_check'

RSpec.describe 'Lint gate helpers (.codex)' do
  def offense(cop, line = 1)
    { 'cop_name' => cop, 'message' => "#{cop} message", 'location' => { 'start_line' => line } }
  end

  def report(files)
    { 'files' => files.map { |path, offenses| { 'path' => path, 'offenses' => offenses } } }
  end

  describe DcfRubocopRatchet do
    let(:base) { report('app/a.rb' => [offense('Style/Foo')]) }

    it 'passes when base and head are identical' do
      result = described_class.compare(base, base)
      expect(result[:regressions]).to be_empty
    end

    it 'fails with a NEW line when a changed file gains an offense' do
      head = report('app/a.rb' => [offense('Style/Foo'), offense('Style/Foo', 7)])
      result = described_class.compare(base, head)
      expect(result[:regressions].size).to eq(2)
      expect(result[:regressions].first).to start_with('NEW app/a.rb:')
    end

    it 'passes and counts the fix when an offense disappears' do
      result = described_class.compare(base, report('app/a.rb' => []))
      expect(result[:regressions]).to be_empty
      expect(result[:summary]).to include('fixed=1')
    end

    it 'requires a file that is new at head to be clean' do
      head = report('app/a.rb' => [offense('Style/Foo')], 'app/new.rb' => [offense('Style/Bar')])
      result = described_class.compare(base, head)
      expect(result[:regressions]).to contain_exactly(a_string_starting_with('NEW app/new.rb:1 Style/Bar'))
    end

    it 'resets the baseline of a file that did not parse under Ruby 2.7 at base' do
      broken = report('spec/x.rb' => [offense('Lint/Syntax')])
      result = described_class.compare(broken, report('spec/x.rb' => [offense('Style/Foo')]))
      expect(result[:regressions]).to be_empty
      expect(result[:infos].first).to include('baseline reset')
    end
  end

  describe DcfCompatCheck do
    def diff(added_line, path = 'app/views/x.html.erb')
      "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n@@ -10,0 +11,1 @@\n+#{added_line}\n"
    end

    it 'accepts an added line without forbidden constructs' do
      expect(described_class.check(diff('<%= link_to "x", y %>'))).to be_empty
    end

    it 'flags javascript_tag on an added line with path and line number' do
      findings = described_class.check(diff('<%= javascript_tag "x" %>'))
      expect(findings.size).to eq(1)
      expect(findings.first[0, 2]).to eq(['app/views/x.html.erb', 11])
    end

    it 'flags an en dash and an em dash' do
      expect(described_class.check(diff("a \u2013 b"))).not_to be_empty
      expect(described_class.check(diff("a \u2014 b"))).not_to be_empty
    end

    it 'flags Ruby 3.1+ and Rails 7+ only APIs' do
      ['list.intersect?(other)', 'params.expect(:id)', 'render(status: :unprocessable_content)'].each do |code|
        expect(described_class.check(diff(code, 'app/x.rb'))).not_to be_empty, code
      end
    end

    it 'ignores removed and context lines' do
      text = "+++ b/app/x.rb\n@@ -3,1 +3,0 @@\n-Rails.cache.delete_matched('x')\n"
      expect(described_class.check(text)).to be_empty
    end

    it 'reads a diff with non-ASCII characters whatever the external encoding is' do
      binary = diff("name = 'S\u00e3o Jo\u00e3o'").dup.force_encoding(Encoding::ASCII_8BIT)
      expect(described_class.check(binary)).to be_empty
    end

    it 'allows specs to name delete_matched and javascript_tag but not production code' do
      expect(described_class.check(diff('expect(cache).not_to have_received(:delete_matched)', 'spec/models/x_spec.rb'))).to be_empty
      expect(described_class.check(diff('Rails.cache.delete_matched("x")', 'lib/x.rb'))).not_to be_empty
      expect(described_class.check(diff("a \u2014 b", 'spec/models/x_spec.rb'))).not_to be_empty
    end

    it 'exempts a line marked dcf-compat-ok' do
      expect(described_class.check(diff('<%= javascript_tag "x" %> <%# dcf-compat-ok %>'))).to be_empty
    end
  end
end
