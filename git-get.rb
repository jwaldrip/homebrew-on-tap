require "formula"

class GitGet < Formula
  VERSION = "0.5.3"
  version VERSION
  desc "A way to clone git repos into a common path"
  homepage "https://github.com/jwaldrip/git-get"
  head "https://github.com/jwaldrip/git-get.git", branch: "master"
  url "https://github.com/jwaldrip/git-get.git", using: :git, tag: "v#{VERSION}"

  depends_on "go" => :build
  depends_on "dep" => :build

  ORIG_ENV = ENV.to_h

  def install
    ENV["GOPATH"] = buildpath
    contents = Dir["{*,.git,.gitignore}"]
    (buildpath/"src/github.com/jwaldrip/git-get").install contents

    ENV.prepend_create_path "PATH", buildpath/"bin"

    cd "src/github.com/jwaldrip/git-get" do
      system "make build"
      bin.install './bin/git-get' => "git-get"
    end
  end

  def caveats
    if ORIG_ENV['GITPATH']
      <<-EOS

        Your git path is set to `#{ORIG_ENV['GITPATH']}`. git-get will clone projects
        to #{ORIG_ENV['GITPATH']}.
      EOS
    elsif ORIG_ENV['GOPATH']
      <<-EOS

        Your go path is set to `#{ORIG_ENV['GOPATH']}`. git-get will clone projects to
        `#{ORIG_ENV['GOPATH']}/src` unless you set GITPATH in your environment.

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
