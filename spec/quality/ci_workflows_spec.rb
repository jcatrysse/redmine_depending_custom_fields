# frozen_string_literal: true

require_relative '../rails_helper'
require 'yaml'

# Owner rule: CI runs only when started manually (workflow_dispatch), never on
# push, pull_request or a schedule. Psych reads the YAML key `on` as boolean true.
RSpec.describe 'GitHub workflows' do
  workflows = Dir[File.expand_path('../../.github/workflows/*.{yml,yaml}', __dir__)].sort

  def triggers_of(doc)
    triggers = doc.key?('on') ? doc['on'] : doc[true]
    triggers.is_a?(Hash) ? triggers.keys.map(&:to_s) : Array(triggers).map(&:to_s)
  end

  it 'exist' do
    expect(workflows).not_to be_empty
  end

  it 'rejects a workflow that would also run on push' do
    doc = YAML.safe_load("on:\n  workflow_dispatch:\n  push:\n")
    expect(triggers_of(doc)).not_to eq(['workflow_dispatch'])
  end

  workflows.each do |path|
    describe File.basename(path) do
      let(:doc) { YAML.safe_load(File.read(path)) }

      it 'is triggered by workflow_dispatch only' do
        expect(triggers_of(doc)).to eq(['workflow_dispatch'])
      end

      it 'grants read-only repository permissions' do
        expect(doc['permissions']).to eq('contents' => 'read')
      end
    end
  end
end
