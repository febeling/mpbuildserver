require "rubygems"
gem "rspec" #, "=1.1.4"
require "spec/rake/spectask"

task :default => [:test]

Spec::Rake::SpecTask.new(:test) do |t|
  t.spec_files = FileList["test/*.rb"]
end
