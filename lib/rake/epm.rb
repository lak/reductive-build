#!/usr/bin/env ruby

# Create EPM packages.

require 'rake/redlabpackage'

module Rake

# Create a packaging task that will package the project into
# distributable files using EPM (http://www.easysw.com/epm).
#
class EPMPackageTask < RedLabPackageTask
    # Verify we have the binaries.
    @epm = %x{which epm 2>/dev/null}
    unless $? == 0
        raise "EPM does not appear to be installed; cannot make EPM packages"
    end
    @mkepmlist = %{which mkepmlist 2>/dev/null}
    unless $? == 0
        raise "EPM does not appear to be installed; cannot make EPM packages"
    end

    # Directory in which to publish epm packages.
    attr_writer :epmpublishdir

    # True if a native package should be produced (default is true).
    attr_accessor :need_native

    # True if a portable EPM-style should be produced (default is false).
    attr_accessor :need_portable

    # Create the tasks defined by this task library.
    def define
        super

        @definedtasks ||= []
        methods.find_all { |method| method.to_s =~ /^mktask/
        }.each { |method|
            unless @definedtasks.include? method
                self.send(method)
            end
        }

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

        task name => [self.epmpublishdir, listfile(), :copycode] do
            sh %{epm --output-dir #{self.epmpublishdir} -f #{pkgtype} #{@name} #{listfile}}
        end
    end

    # We have to do it this way, because of the order in which the initialize
    # and define stuff is done.
    def epmpublishdir
        unless defined? @epmpublishdir
            unless self.pkgpublishdir
                raise "The package publish dir is unset"
            end
            # Set the directory in which we make packages
            @epmpublishdir = File.join(
                self.package_dir,
                "epm",
                Facter["operatingsystem"].value
            )
        end

        @epmpublishdir
    end

    # Create the header of our list file.
    def header
        # Create our list header
        puts "making header with version #{@version}"
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
    end

    # The path to the listfile
    def listfile
        unless defined? @listfile
            @listfile = File.join(package_dir, "#{@name}-#{@os}.list")
        end

        return @listfile
    end

    def mktaskoutputdir
        directory self.epmpublishdir
    end

    # Create the task that creates our list file.
    def mktasklistfile
        file(listfile() => [:copycode]) do
            type = nil

            # The path to the listfile
            listfile = File.join(package_dir, "#{@name}-#{@os}.list")

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

    def outputdir
        return File.join(package_dir, "epm")
    end
end
end

# $Id$
