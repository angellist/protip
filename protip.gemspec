# encoding: utf-8

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "protip/version"

Gem::Specification.new do |spec|
  spec.name          = 'protip'
  spec.version       = Protip::VERSION
  spec.summary       = 'Relatively painless protocol buffers in Ruby.'
  spec.licenses      = ['MIT']
  spec.homepage      = 'https://github.com/AngelList/protip'
  spec.summary       = 'Resources backed by protobuf messages'
  spec.authors       = ['AngelList']
  spec.email         = ['team@angel.co']
  spec.files         = Dir['lib/**/*.rb'] +
                       Dir['lib/**/*.rake'] +
                       Dir['test/**/*.rb'] +
                       Dir['definitions/**/*.proto'] +
                       Dir['build/**/*.rb']

  spec.required_ruby_version = '>= 2.1.0'

  spec.add_runtime_dependency 'activemodel', '>= 4.2.10'
  spec.add_runtime_dependency 'activesupport', '>= 4.2.10'
  spec.add_runtime_dependency 'money', '>= 6.5.1', '< 7.0'
  spec.add_runtime_dependency 'google-protobuf', '>= 3.7.1'
  spec.add_runtime_dependency 'faraday', '< 3'
  spec.add_runtime_dependency 'faraday-retry'

  spec.add_development_dependency 'grpc-tools', '1.48.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'minitest-stub-const', '~> 0.6'
  spec.add_development_dependency 'mocha', '~> 1.11'
  spec.add_development_dependency 'rake', '>= 12.3.3'
  spec.add_development_dependency 'simplecov', '~> 0.18'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'webmock', '~> 3'
end
