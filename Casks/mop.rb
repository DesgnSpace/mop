cask "mop" do
  version "1.5.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://downloads.desgn.space/mop/MOP-#{version}.zip"
  name "MOP"
  desc "Voice-to-text for macOS that runs entirely on your machine"
  homepage "https://mop.desgn.space"

  livecheck do
    url "https://downloads.desgn.space/mop/releases.json"
    strategy :json do |json|
      json["latest"]
    end
  end

  depends_on macos: ">= :sonoma"

  app "MOP.app"
end
