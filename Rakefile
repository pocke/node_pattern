require 'rspec/core/rake_task'
require "bundler/gem_tasks"

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

task :default => %i[kpeg spec]

task :kpeg do
  sh "kpeg -s -f lib/node_pattern/parser.kpeg"
end
