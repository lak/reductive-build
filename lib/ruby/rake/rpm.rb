#!/usr/bin/env ruby

# Create EPM packages.

require 'rake/redlabpackage'

module Rake

# Create a packaging task that will package the project into
# distributable files using EPM (http://www.easysw.com/epm).
#
# The PackageTask will create the following targets:
#
# [<b>:epmpackage</b>]
#   Create all the requested package files.
#
# [<b>:clobber_package</b>]
#   Delete all the package files.  This target is automatically
#   added to the main clobber target.
#
# [<b>:repackage</b>]
#   Rebuild the package files from scratch, even if they are not out
#   of date.
#
# [<b>"<em>package_dir</em>/<em>name</em>-<em>version</em>.tgz"</b>]
#   Create a gzipped tar package (if <em>need_tar</em> is true).  
#
# [<b>"<em>package_dir</em>/<em>name</em>-<em>version</em>.tar.gz"</b>]
#   Create a gzipped tar package (if <em>need_tar_gz</em> is true).  
#
# [<b>"<em>package_dir</em>/<em>name</em>-<em>version</em>.tar.bz2"</b>]
#   Create a bzip2'd tar package (if <em>need_tar_bz2</em> is true).  
#
# [<b>"<em>package_dir</em>/<em>name</em>-<em>version</em>.zip"</b>]
#   Create a zip package archive (if <em>need_zip</em> is true).
#
# Example:
#
#   Rake::PackageTask.new("rake", "1.2.3") do |p|
#     p.need_tar = true
#     p.package_files.include("lib/**/*.rb")
#   end
#
class EPMPackageTask < RedLabPackageTask
    # True if a native package should be produced (default is true).
    attr_accessor :need_native

    # True if a portable EPM-style should be produced (default is false).
    attr_accessor :need_portable

    # Create the tasks defined by this task library.
    def define
        super

        mklistfiletask()

        if need_native
            epmpackage("native")
        end
        
        if need_portable
            epmpackage("portable")
        end

        self
    end

    # Return the list of files associated with the given type.
    def epmlist(dir, prefix)
        cmd = %{mkepmlist --prefix #{prefix} #{dir}}
        puts cmd
        list = %x{#{cmd}}.gsub("luke", "0")

        return list
    end

    # Create the task that creates our package, of various types (native or portable).
    def epmpackage(pkgtype)
        name = "epm#{pkgtype}".intern

        task name => [listfile(), :copycode] do
            sh %{epm -n --output-dir #{package_dir} -f #{pkgtype} #{@name} #{listfile}}
        end
    end

    # Create the header of our list file.
    def header
        # Create our list header
        unless defined? @header
            header = []
            %w{product copyright vendor license readme description
            version}.each do |attr|
                header << "%#{attr} #{self.send(attr)}"
            end

            @requires.each do |name, version|
                if version
                    header << "%requires #{name} #{version}"
                else
                    header << "%requires #{name}"
                end
            end

            @header = header.join("\n")
        end

        return @header
    end

    # Create a Package Task with the given name and version. 
    def initialize(name=nil, version=nil)
        @need_native    = true
        @need_portable  = true

        super

        # Verify we have the binaries.
        @epm = %x{which epm 2>/dev/null}
        unless $? == 0
            raise "EPM does not appear to be installed; cannot make EPM packages"
        end
        @mkepmlist = %{which mkepmlist 2>/dev/null}
        unless $? == 0
            raise "EPM does not appear to be installed; cannot make EPM packages"
        end
    end

    # The path to the listfile
    def listfile
        unless defined? @listfile
            @listfile = File.join(package_dir, "#{@name}-#{OS}.list")
        end

        return @listfile
    end

    # Create the task that creates our list file.
    def mklistfiletask
        file(listfile() => [:copycode]) do
            type = nil

            # The path to the listfile
            listfile = File.join(package_dir, "#{@name}-#{OS}.list")

            File.open(listfile, "w") do |f|
                f.puts self.header

                @dirtypes.each do |dirname, dirmethod|
                    targetdir = targetdir(dirname)

                    if list = self.epmlist(targetdir, self.send(dirname))
                        f.puts list
                    end
                end
            end
        end
    end
end
end

# $Id$
