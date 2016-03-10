require 'shellwords'
namespace :protip do
  desc 'compile a single .proto file to Ruby'
  task :compile, [:filename, :proto_path, :ruby_path] do |t, args|
    proto_path = [args[:proto_path] || 'definitions'].flatten.compact.reject{|path| path == ''}
    proto_path << File.join(Gem.loaded_specs['protip'].full_gem_path, 'definitions')

    ruby_path = args[:ruby_path] || 'lib'

    filename = args[:filename] || raise(ArgumentError.new 'filename argument is required')

    command = "protoc #{proto_path.map{|p| "--proto_path=#{Shellwords.escape p}"}.join ' '} --ruby_out=#{Shellwords.escape ruby_path} #{Shellwords.escape filename}"
    puts command # is there a better way to log this?
    system command

    ## hack around missing options in Ruby, remove when https://github.com/google/protobuf/issues/1198 is resolved
    package_match = File.read(filename).match(/package "?([a-zA-Z0-9\.]+)"?;/)
    package = (package_match ? package_match[1] : nil)
    ruby_file = filename.gsub(/^#{proto_path.first}\/?/, "#{ruby_path}/").gsub(/proto$/, 'rb') # Relies on a relative filename and proto path, which protoc requires anyway at this point
    raise "cannot find generated Ruby file (#{ruby_file})" unless File.exists?(ruby_file)

    # Push/pop message names as we move through the protobuf file
    message_name_stack = []
    first_match = true
    File.open filename, 'r' do |f|
      f.each_line do |line|
        if line.include? '{'
          match = line.match(/message\s([a-zA-Z]+)/)
          message_name_stack << (match ? match[1] : nil)
        end

        # figure out the field name and enum name if this line is like
        # +protip.messages.EnumValue value = 3 [(protip_enum) = "Foo"]+
        match = line.match /\s*[a-zA-Z0-9\.]+\s+([a-zA-Z0-9]+).+\[\s*\(\s*protip_enum\s*\)\s*=\s*"([a-zA-Z0-9\.]+)"\s*\]/
        if match
          message_name = "#{package ? "#{package}." : ''}#{message_name_stack.compact.join('.')}"
          field_name = match[1]
          enum_name = match[2]
          File.open ruby_file, 'a' do |f|
            if first_match
              f.puts <<-RBY

# -- Protip hack until https://github.com/google/protobuf/issues/1198 is resolved
RBY
            end
            first_match = false
            f.puts <<-RBY
Google::Protobuf::DescriptorPool.generated_pool.lookup("#{message_name}").lookup("#{field_name}").instance_variable_set(:"@_protip_enum_value", "#{enum_name}")
RBY
          end
        end

        if line.include? '}'
          message_name_stack.pop
        end
      end
    end

  end
end