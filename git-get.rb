require "formula"

class GitGet < Formula
  VERSION = "0.1.0"

  version VERSION
  homepage "https://github.com/jwaldrip/git-get"
  head "https://github.com/jwaldrip/git-get.git", branch: "master"
  url "https://github.com/jwaldrip/git-get.git", using: :git, tag: "v#{VERSION}"

  depends_on "libssh2" => :build
  depends_on "pkg-config" => :build
  depends_on "cmake" => :build
  depends_on "go" => :build
  depends_on "libgit2"

  def install
    gopath, _ = FileUtils.mkdir_p(File.join(buildpath, "gopath"))
    system("GOPATH=#{gopath} make build")
    bin.install "./bin/git-get" => "git-get"
  end

  def caveats
    if ENV['GITPATH']
      <<-EOS.undent

        Your git path is set to `#{ENV['GITPATH']}`. git-get will clone projects
        to #{ENV['GITPATH']}.
      EOS
    elsif ENV['GOPATH']
      <<-EOS.undent

        Your go path is set to `#{ENV['GOPATH']}`. git-get will clone projects to
        `#{ENV['GOPATH']}/src` unless you set GITPATH in your environment.

        EXAMPLE:
        $ echo "export GITPATH=$HOME/dev" > .bashprofile

      EOS
    else
      <<-EOS.undent

        Be sure to set your GITPATH or GOPATH before using git-get.

        EXAMPLE:
        $ echo "export GITPATH=$HOME/dev" > .bashprofile

      EOS
    end
  end

  test do
    path = testpath
    Kernel.system({ "GITPATH" => path.to_s }, "#{bin}/git-get", "https://github.com/jwaldrip/git-get.git", out: '/dev/null', err: '/dev/null')
    assert File.exist?("#{path}/github.com/jwaldrip/git-get/.git")
  end
end
