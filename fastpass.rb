require "net/http"
require "formula"

class Fastpass < Formula
  LATEST_RELEASE = JSON.parse(Net::HTTP.get(URI("https://api.github.com/repos/jwaldrip/fastpass/releases/latest")))
  TAG = LATEST_RELEASE && LATEST_RELEASE["tag_name"]

  version TAG&.sub /^v/, ''
  homepage 'https://github.com/jwaldrip/fastpass'
  head 'https://github.com/jwaldrip/fastpass.git', branch: 'master'
  url 'https://github.com/jwaldrip/fastpass.git', using: :git, tag: TAG

  depends_on 'crystal'

  def install
    system 'shards build --production'
    bin.install "bin/fastpass"
  end
end
