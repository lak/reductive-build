# Rakefile for the build system

require 'rbconfig'

sitedir = Config::CONFIG["sitelibdir"]

files = Dir.glob("lib/**/*.rb")

tasks = []

files.each do |path|

    dfile = File.join(sitedir, path.sub(/^\w+\//, ''))
    dir = File.dirname(dfile)
    directory dir
    tasks << dfile
    file dfile => [dir, path] do
        FileUtils.install(path, dfile, :mode => 0644, :verbose => true)
    end
end

task :install => tasks do
end

task :default => :install

# $Id$
