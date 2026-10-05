# frozen_string_literal: true

require_relative '../rails_helper'

# Owner style: no en dash or em dash characters in user-facing texts. The lint
# gate (.codex/lib/compat_check.rb) covers added code lines; this spec covers
# the documents and locale files users read.
RSpec.describe 'User-facing texts' do
  root = File.expand_path('../..', __dir__)
  files = [File.join(root, 'README.md'), File.join(root, 'CHANGELOG.md')] +
          Dir[File.join(root, 'config/locales/*.yml')].sort

  files.each do |file|
    it "#{File.basename(file)} contains no en dash or em dash" do
      offending = File.readlines(file, encoding: 'UTF-8').each_with_index.select do |line, _|
        line.match?(/[\u2013\u2014]/)
      end
      expect(offending.map { |line, index| "#{index + 1}: #{line.strip}" }).to eq([])
    end
  end
end
