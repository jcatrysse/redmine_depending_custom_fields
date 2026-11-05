# frozen_string_literal: true

require_relative '../rails_helper'

# Full branch review of 2026-11-05 (issue-form-1, admin-editor-1): the
# plugin stylesheets use logical properties, so indents land on the start
# side in right-to-left languages (Redmine ships ar, fa and he), and an
# element the editor hides with the hidden attribute stays hidden although
# a rule of the editor gives it display: flex (author rules beat the
# browser's [hidden] rule, and Redmine has no global one).
RSpec.describe 'Plugin stylesheets' do
  root = File.expand_path('../..', __dir__)
  sheets = Dir[File.join(root, 'assets/stylesheets/*.css')].sort

  sheets.each do |sheet|
    it "#{File.basename(sheet)} uses no physical left or right margin, padding or float" do
      css = File.read(sheet).gsub(%r{/\*.*?\*/}m, '')
      physical = css.scan(/(?:margin|padding|border)-(?:left|right)\s*:|float\s*:\s*(?:left|right)|text-align\s*:\s*(?:left|right)/)
      expect(physical).to eq([])
    end
  end

  it 'keeps elements of the dependency editor with the hidden attribute hidden' do
    css = File.read(File.join(root, 'assets/stylesheets/dcf_dependency_editor.css'))
    expect(css).to match(/\.dcf-dep-editor \[hidden\]\s*\{\s*display:\s*none\s*!important;\s*\}/)
  end
end
