require "net/http"
require "formula"
require "language/node"

class Fastpass < Formula
  LATEST_RELEASE = JSON.parse(Net::HTTP.get(URI("https://api.github.com/repos/jwaldrip/fastpass/releases/latest")))
  FALLBACK_TAG = "v1.9.3.0"
  TAG = LATEST_RELEASE["tag_name"] || FALLBACK_TAG

  version TAG.sub /^v/, ''
  homepage 'https://github.com/jwaldrip/fastpass'
  head 'https://github.com/jwaldrip/fastpass.git', branch: 'master'
  url 'https://github.com/jwaldrip/fastpass.git', using: :git, tag: TAG

  depends_on 'crystal-lang' => :build
  depends_on 'openssl' => :build
  depends_on 'node' => :build
  depends_on 'kubernetes-cli'
  depends_on 'bdw-gc'

  def install
    ENV["TRAVIS_TAG"] = TAG unless build.head?
    system 'shards build --release'
    bin.install "bin/fastpass"
  end
end
