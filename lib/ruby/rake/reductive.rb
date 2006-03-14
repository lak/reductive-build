# Rakefile library for Reductive Labs projects

require 'facter'

# Determine the current version

unless defined? PKG
    raise "You must set the package name in PKG"
end

if %x{ruby -Ilib ./bin/#{PKG} --version} =~ /\S+$/
    CURRENT_VERSION = $&
else
    CURRENT_VERSION = "0.0.0"
end

if ENV['REL']
  PKG_VERSION = ENV['REL']
else
  PKG_VERSION = CURRENT_VERSION
end

DOWNDIR = "/export/docroots/reductivelabs.com/htdocs/downloads"

OS = Facter["operatingsystem"].value

$sitedir = $:.find { |d| d =~ /site_ruby$/ }

unless $sitedir
    raise "Could not find site_ruby directory"
end
desc "Install the application"
task :install do
    ruby "install.rb"
end

def announce(msg='')
    STDERR.puts msg
end

unless defined? PACKAGES
    PACKAGES = 
end

# --------------------------------------------------------------------
# Creating a release

desc "Make a new release"
task :release => [
        :prerelease,
        :clobber,
        :update_version,
        :tag, # tag everything before we make a bunch of extra dirs
        :html,
        :packages,
        :copy
      ] do
  
    announce 
    announce "**************************************************************"
    announce "* Release #{PKG_VERSION} Complete."
    announce "* Packages ready to upload."
    announce "**************************************************************"
    announce 
end

# Validate that everything is ready to go for a release.
task :prerelease do
    announce 
    announce "**************************************************************"
    announce "* Making RubyGem Release #{PKG_VERSION}"
    announce "* (current version #{CURRENT_VERSION})"
    announce "**************************************************************"
    announce  

    # Is a release number supplied?
    unless ENV['REL']
        fail "Usage: rake release REL=x.y.z [REUSE=tag_suffix]"
    end

    # Is the release different than the current release.
    # (or is REUSE set?)
    if PKG_VERSION == CURRENT_VERSION && ! ENV['REUSE']
        fail "Current version is #{PKG_VERSION}, must specify REUSE=tag_suffix to reuse version"
    end

    # Are all source files checked in?
    if ENV['RELTEST']
        announce "Release Task Testing, skipping checked-in file test"
    else
        announce "Checking for unchecked-in files..."
        data = `svn -q update`
        unless data =~ /^$/
            fail "SVN update is not clean ... do you have unchecked-in files?"
        end
        announce "No outstanding checkins found ... OK"
    end
end

task :update_version => [:prerelease] do
    if PKG_VERSION == CURRENT_VERSION
        announce "No version change ... skipping version update"
    else
        announce "Updating #{PKG} version to #{PKG_VERSION}"
        open("lib/#{PKG}.rb") do |rakein|
            open("lib/#{PKG}.rb.new", "w") do |rakeout|
                rakein.each do |line|
                    if line =~ /^(\s*)#{PKG.upcase}VERSION\s*=\s*/
                        rakeout.puts "#{$1}#{PKG.upcase}VERSION = '#{PKG_VERSION}'"
                    else
                        rakeout.puts line
                    end
                end
            end
        end
        mv "lib/#{PKG}.rb.new", "lib/#{PKG}.rb"

        open("conf/redhat/#{PKG}.spec") do |rakein|
            open("conf/redhat/#{PKG}.spec.new", "w") do |rakeout|
                rakein.each do |line|
                    if line =~ /^Version:\s*/
                        rakeout.puts "Version: #{PKG_VERSION}"
                    elsif line =~ /^Release:\s*/
                      rakeout.puts "Release: 1%{?dist}"
                    else
                        rakeout.puts line
                    end
                end
            end
        end
        mv "conf/redhat/#{PKG}.spec.new", "conf/redhat/#{PKG}.spec"

        if ENV['RELTEST']
            announce "Release Task Testing, skipping commiting of new version"
        else
            sh %{svn commit -m "Updated to version #{PKG_VERSION}" lib/#{PKG}.rb conf/redhat/#{PKG}.spec}
        end
    end
end

desc "Copy the newly created package into the downloads directory"
task :copy => [:package, :html, :fedorarpm] do
    unless Facter["hostname"].value == PKGHOST
        $stderr.puts "Not on package host; not copying"
    end
    sh %{cp pkg/#{PKG}-#{PKG_VERSION}.gem #{DOWNDIR}/gems}
    sh %{generate_yaml_index.rb -d #{DOWNDIR}}
    sh %{cp pkg/#{PKG}-#{PKG_VERSION}.tgz #{DOWNDIR}/#{PKG}}
    sh %{ln -sf #{PKG}-#{PKG_VERSION}.tgz #{DOWNDIR}/#{PKG}/#{PKG}-latest.tgz}
    sh %{cp -r html #{DOWNDIR}/#{PKG}/apidocs}
    if defined? RPMDIR
        sh %{rsync -av #{RPMDIR}/ #{DOWNDIR}/rpm/}
    end

    if defined? EPMDIR
        sh %{rsync -av #{EPMDIR}/ #{DOWNDIR}/packages/}
    end
end

desc "Tag all the SVN files with the latest release number (REL=x.y.z)"
task :tag => [:prerelease] do
    reltag = "REL_#{PKG_VERSION.gsub(/\./, '_')}"
    reltag << ENV['REUSE'].gsub(/\./, '_') if ENV['REUSE']
    announce "Tagging SVN copy with [#{reltag}]"
    if ENV['RELTEST']
        announce "Release Task Testing, skipping SVN tagging"
    else
        sh %{svn copy ../trunk/ ../tags/#{reltag}}
        sh %{cd ../tags; svn ci -m "Adding release tag #{reltag}"}
    end
end

desc "Test our package on each test host"
task :hosttest do
    hosts = nil
    if ENV['HOSTS']
        hosts = ENV['HOSTS'].split(/\s+/)
    else
        if defined? TESTHOSTS
            hosts = TESTHOSTS
        else
            $stderr.puts "No test hosts defined; cannot test across platforms"
            return
        end
    end

    out = ""
    hosts.each do |host|
        puts "testing %s" % host
        cwd = Dir.getwd
        system("ssh #{host} 'cd #{PKG}/test; sudo ./test' 2>&1 >/tmp/#{PKG}-#{host}test.out")

        if $? != 0
            puts "%s failed; output is in %s" % [host, file]
        end
    done
end

desc "Make all of the different packages"

desc "Create an RPM"
task :rpm do
    RPMDIR = %x{rpm --define 'name #{PKG}' --define 'version #{PKG_VERSION}' --eval '%_topdir'`}
    tarball = File.join(Dir.getwd, "pkg", "#{PKG}-#{PKG_VERSION}.tgz")

    sourcedir = `rpm --define 'name #{PKG}' --define 'version #{PKG_VERSION}' --eval '%_sourcedir'`.chomp
    specdir = `rpm --define 'name #{PKG}' --define 'version #{PKG_VERSION}' --eval '%_specdir'`.chomp
    basedir = File.dirname(sourcedir)

    if ! FileTest::exist?(sourcedir)
        FileUtils.mkdir_p(sourcedir)
    end
    FileUtils.mkdir_p(basedir)

    target = "#{sourcedir}/#{File::basename(tarball)}"

    sh %{cp %s %s} % [tarball, target]
    sh %{cp conf/redhat/#{PKG}.spec %s/#{PKG}.spec} % basedir

    Dir.chdir(basedir) do
        sh %{rpmbuild -ba #{PKG}.spec}
    end

    sh %{mv %s/#{PKG}.spec %s} % [basedir, specdir]
end

desc "Create an rpm on a system that can actually do so"
task :fedorarpm => [:package] do
    sh %{ssh fedora1 'cd svn/#{PKG}/trunk; rake rpm'}
end

def epmlist(match, prefix = "/usr")
    dest = "../epmtmp/#{OS}-#{match}"

    list = %x{mkepmlist --prefix #{prefix} ../#{PKG}-#{PKG_VERSION}}.gsub(/luke/, "0")

    list = list.split(/\n/).find_all do |line|
        line =~ /#{prefix}\/#{match}/
    end.join("\n")

    File.open(dest, "w") { |f| f.puts list }

    return dest
end

directory "pkg/epm"
directory "pkg/epmtmp"

desc "Create packages using EPM"
task :epmpkg => ["pkg/epm", "pkg/epmtmp", :package] do
    $epmdir = "pkg/epm"
    $epmtmpdir = "pkg/epmtmp"

    Dir.chdir($epmdir) do
        type = nil

        binfile = epmlist("bin", "/usr")
        libfile = epmlist("lib", $sitedir)

        listfile = "../epmtmp/#{OS}.list"
        sh %{cat ../../conf/epm.list #{binfile} #{libfile} > #{listfile}}
        sh %{epm -f native #{PKG} #{listfile}}
    end

    EPMDIR = "pkg/epm"
end

# $Id$
