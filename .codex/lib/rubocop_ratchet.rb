# frozen_string_literal: true

# Compares two RuboCop JSON reports per (file, cop). A file/cop whose offense
# count grew is a regression; a file that is new at head must be clean. Plain
# Ruby, no gems: runs on any Ruby >= 2.7.
#
#   ruby .codex/lib/rubocop_ratchet.rb base.json head.json
#
# Prints evidence lines and exits 1 on regression.
require 'json'

module DcfRubocopRatchet
  module_function

  # path => [offense, ...]
  def offenses_by_path(report)
    report.fetch('files').to_h { |file| [file['path'], file['offenses']] }
  end

  # Returns { regressions: [String], infos: [String], summary: String }.
  def compare(base_report, head_report)
    base = offenses_by_path(base_report)
    head = offenses_by_path(head_report)
    regressions = []
    infos = []
    fixed = 0
    head.each do |path, offenses|
      if (base[path] || []).any? { |o| o['cop_name'] == 'Lint/Syntax' }
        # The base file did not parse under Ruby 2.7, so its per-cop counts are
        # meaningless. The syntax gate covers it; this change resets its baseline.
        infos << "INFO #{path}: base not parseable under Ruby 2.7, baseline reset (#{offenses.size} offenses now)"
        next
      end
      before = (base[path] || []).group_by { |o| o['cop_name'] }
      offenses.group_by { |o| o['cop_name'] }.each do |cop, list|
        allowed = (before[cop] || []).size
        next unless list.size > allowed

        list.each do |o|
          regressions << format('NEW %<p>s:%<l>d %<c>s %<m>s (base %<b>d, head %<h>d)',
                                p: path, l: o['location']['start_line'], c: cop,
                                m: o['message'], b: allowed, h: list.size)
        end
      end
      before.each do |cop, list|
        fixed += [list.size - offenses.count { |o| o['cop_name'] == cop }, 0].max
      end
    end
    summary = format('files=%<f>d base_offenses=%<b>d head_offenses=%<h>d fixed=%<x>d',
                     f: head.size, b: base.values.sum(&:size), h: head.values.sum(&:size), x: fixed)
    { regressions: regressions, infos: infos, summary: summary }
  end
end

if $0 == __FILE__
  result = DcfRubocopRatchet.compare(JSON.parse(File.read(ARGV.fetch(0))),
                                     JSON.parse(File.read(ARGV.fetch(1))))
  puts result[:infos]
  puts result[:regressions]
  if result[:regressions].empty?
    puts "RATCHET PASS #{result[:summary]}"
  else
    puts "RATCHET FAIL #{result[:summary]} new=#{result[:regressions].size}"
    exit 1
  end
end
