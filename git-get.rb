require "formula"
require "language/go"

class GitGet < Formula
  homepage "https://github.com/jwaldrip/git-get/"
  url "https://github.com/jwaldrip/git-get/archive/v0.1.0.tar.gz"
  sha1 "a7f287b0292a94673024ea8d009ed2e835807454"
  head "https://github.com/jwaldrip/git-get.git"

  depends_on "openssl"
  depends_on "libssh2"

  depends_on "go" => :build

  # For git2go
  depends_on "pkg-config" => :build
  depends_on "cmake" => :build

  go_resource "github.com/jwaldrip/odin" do
    url "https://github.com/jwaldrip/odin.git", tag: "v1.6.0"
  end

  go_resource "github.com/jwaldrip/tint" do
    url "https://github.com/jwaldrip/tint.git"
  end

  go_resource "github.com/bgentry/speakeasy" do
    url "https://github.com/bgentry/speakeasy.git",
      :revision => "5dfe43257d1f86b96484e760f2f0c4e2559089c7"
  end

  go_resource "github.com/libgit2/git2go" do
    url "https://github.com/libgit2/git2go.git",
      :revision => "41008af54cfc2af3a5ea56dff169c95d2b50dda6"
  end

  def install
    mkdir_p buildpath/"src/github.com/jwaldrip"
    ln_s buildpath, buildpath/"src/github.com/jwaldrip/git-get"

    ENV["GOPATH"] = buildpath
    Language::Go.stage_deps resources, buildpath/"src"

    ENV.append "CGO_CFLAGS", "-I#{buildpath}/src/github.com/libgit2/git2go/vendor/libgit2/include"
    ENV.append "CGO_LDFLAGS", "-L#{Formula["openssl"].lib} -lssl -lcrypto -lz -liconv -L#{Formula["libssh2"].lib} -lssh2 -L#{buildpath}/src/github.com/libgit2/git2go/vendor/libgit2/build -lgit2"

    Dir.chdir "src/github.com/libgit2/git2go" do
      system "make", "install"
    end

    system "go", "build", "-o", "git-get"
    bin.install "git-get"
  end

  test do
    ENV["GITPATH"] = testpath
    system "#{bin}/git-get", "https://github.com/jwaldrip/git-get.git"
    assert File.exist? "github.com/jwaldrip/git-get/.git"
  end
end
