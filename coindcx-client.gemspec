# frozen_string_literal: true

require_relative 'lib/coindcx/version'

Gem::Specification.new do |spec|
  spec.name = 'coindcx-client'
  spec.version = CoinDCX::VERSION
  spec.authors = ['Cursor']
  spec.email = ['noreply@example.com']
  spec.summary = 'Ruby client for CoinDCX REST and Socket.io APIs'
  spec.description =
    'CoinDCX-specific gem with separate REST and Socket.io layers, modeled after layered exchange client architecture.'
  spec.homepage = 'https://github.com/shubhamtaywade82/coindcx-client'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir.chdir(__dir__) do
    Dir[
      'README.md',
      'AGENT.md',
      'bin/console',
      'docs/**/*.md',
      'lib/**/*.rb',
      'spec/**/*.rb',
      '.github/workflows/*.yml',
      '.rubocop.yml'
    ]
  end
  spec.require_paths = ['lib']
  spec.add_dependency 'faraday', '~> 2.14'
  spec.add_dependency 'socket.io-client-simple', '~> 1.2'
end
