class ContextMenuWizardController < ApplicationController
  accept_api_auth :options, :save if respond_to?(:accept_api_auth)

  def options
    render json: [
      { id: 1, name: 'Sample value 1' },
      { id: 2, name: 'Sample value 2' }
    ]
  end

  def save
    head :ok
  end
end
