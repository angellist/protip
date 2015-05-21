require 'bundler/gem_tasks'
require 'fileutils'
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end
task default: :test

namespace :test do
  task :coverage do
    require 'simplecov'
    SimpleCov.command_name 'Unit Tests'
    SimpleCov.start
    Rake::Task['test'].execute
  end
end

=begin
# Can't use this until https://github.com/ruby-protobuf/protobuf/commit/e6b9b1ab68af86b0bb26730e0a9160992614ff1d is merged.
# Do it manually (see below) for now
load 'protobuf/tasks/compile.rake'
task :compile do
  Rake::Tasks['protobuf:compile'].invoke('protip/messages')
end
=end


desc 'Compile protobuf sources to Ruby classes.'
task compile: :clean do
  command = []
  command << 'protoc'
  command << '--ruby_out=lib'
  command << '-I definitions'
  command << 'definitions/protip/messages/*.proto'
  full_command = command.join(' ')

  puts full_command
  exec(full_command)
end

desc 'Remove generated Ruby classes.'
task :clean do
  ::Dir.glob('lib/**/*.pb.rb').each do |file|
    ::FileUtils.rm(file)
  end
end

desc 'Open a console with this gem loaded'
task :console do
  require 'irb'
  require 'irb/completion'
  require 'protip'
  ARGV.clear
  IRB.start
end
