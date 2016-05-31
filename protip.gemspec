# encoding: utf-8
Gem::Specification.new do |spec|
  spec.name          = 'protip'
  spec.version       = '0.20.6'
  spec.summary       = 'Relatively painless protocol buffers in Ruby.'
  spec.licenses      = ['MIT']
  spec.homepage      = 'https://github.com/AngelList/protip'
  spec.summary       = 'Resources backed by protobuf messages'
  spec.authors       = ['AngelList']
  spec.email         = ['team@angel.co', 'k2@angel.co', 'brian@angel.co', 'paul@angel.co']
  spec.files         = Dir['lib/**/*.rb'] +
                       Dir['lib/**/*.rake'] +
                       Dir['test/**/*.rb'] +
                       Dir['definitions/**/*.proto'] +
                       Dir['build/**/*.rb']

  spec.required_ruby_version = '>= 2.1.0'

  spec.add_runtime_dependency 'activemodel', '>= 3.0.0', '< 5.0'
  spec.add_runtime_dependency 'activesupport', '>= 3.0.0', '< 5.0'
  spec.add_runtime_dependency 'google-protobuf', '>= 3.0.0.alpha.5.0.5.1'
  spec.add_runtime_dependency 'money', '>= 6.5.1', '< 7.0'

  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'minitest-stub-const', '~> 0.5'
  spec.add_development_dependency 'mocha', '~> 1.1'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'simplecov', '~> 0.10'
  spec.add_development_dependency 'webmock', '~> 1.20'
end
