# frozen_string_literal: true

# Compat gate for ADDED lines of a unified diff (git diff -U0 <base>), read from
# stdin. Flags constructs that parse on Ruby 2.7 but fail at runtime on the
# oldest supported stack (Ruby 2.7 / Rails 6.1 / Rack 2.2), and constructs that
# break repository rules. A line containing the marker dcf-compat-ok is exempt.
#
#   git diff -U0 origin/main -- app lib | ruby .codex/lib/compat_check.rb
#
# Exits 1 when an added line matches. Plain Ruby, no gems.
module DcfCompatCheck
  RULES = [
    [/\.intersect\?\(/, 'Array#intersect? needs Ruby 3.1'],
    [/\bData\.define\b/, 'Data.define needs Ruby 3.2'],
    [/\bparams\.expect\(/, 'params.expect needs Rails 8'],
    [/:unprocessable_content\b/, ':unprocessable_content raises on Rack 2.2, use 422'],
    [/\bin_order_of\b/, 'in_order_of needs Rails 7'],
    [/\bnormalizes\b/, 'normalizes needs Rails 7.1'],
    [/Rails\.configuration\.to_prepare/, 'repository rule: no to_prepare in init.rb'],
    [/\bdelete_matched\b/, 'delete_matched raises NotImplementedError on MemCacheStore'],
    [/\bjavascript_tag\b/, 'no inline script tags (CSP, point 1)'],
    [/[\u2013\u2014]/, 'no en dash or em dash characters (owner style)']
  ].freeze
  EXEMPT = 'dcf-compat-ok'

  module_function

  # Returns [[path, line_number, message, text], ...] for offending added lines.
  def check(diff)
    findings = []
    path = nil
    line_no = 0
    utf8(diff).each_line do |raw|
      line = raw.chomp
      if line.start_with?('+++ ')
        path = line.sub(%r{\A\+\+\+ (b/)?}, '')
      elsif (m = line.match(/\A@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
        line_no = m[1].to_i
      elsif line.start_with?('+')
        text = line[1..-1]
        unless text.include?(EXEMPT)
          RULES.each do |pattern, message|
            findings << [path, line_no, message, text.strip] if pattern.match?(text)
          end
        end
        line_no += 1
      end
    end
    findings
  end

  # git output is UTF-8 whatever the process locale (LANG may be unset).
  def utf8(text)
    text.dup.force_encoding(Encoding::UTF_8).scrub
  end
end

if $0 == __FILE__
  findings = DcfCompatCheck.check($stdin.read)
  findings.each { |path, line, message, text| puts "#{path}:#{line}: #{message}: #{text}" }
  if findings.empty?
    puts 'COMPAT PASS'
  else
    puts "COMPAT FAIL (#{findings.size})"
    exit 1
  end
end
