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
  depends_on "git"

  def install
    system "make", "build"
    bin.install "./bin/git-get" => "git-get"
  end

  test do
    path = testpath
    system "GITPATH=#{path}", "#{bin}/git-get", "https://github.com/jwaldrip/git-get.git"
    assert File.exist?("#{path}/github.com/jwaldrip/git-get/.git")
  end
end
