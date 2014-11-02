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
  depends_on "git" => :build

  orig_env = ENV.dup

  def install
    ENV["GIT_DIR"] = cached_download/".git" if build.head?
    ENV["GOBIN"] = bin
    ENV["GOPATH"] = buildpath
    ENV["GOHOME"] = buildpath
    srcpath, _ = mkdir_p File.join buildpath, "/src/github.com/jwaldrip"
    ln_s Dir.pwd, File.join(srcpath, 'git-get')
    system("go env")
    system("make build")
    bin.install "./bin/git-get" => "git-get"
  end

  def caveats
    if orig_env['GITPATH']
      <<-EOS.undent

        Your git path is set to `#{orig_env['GITPATH']}`. git-get will clone projects
        to #{orig_env['GITPATH']}.
      EOS
    elsif orig_env['GOPATH']
      <<-EOS.undent

        Your go path is set to `#{orig_env['GOPATH']}`. git-get will clone projects to
        `#{orig_env['GOPATH']}/src` unless you set GITPATH in your environment.

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
