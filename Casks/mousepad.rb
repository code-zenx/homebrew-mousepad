cask "mousepad" do
  version "0.1.0"
  sha256 "1de5938cf7907d3fb8758620983a1b598461e24401b87193a322d7456cd27d17"

  url "https://github.com/code-zenx/homebrew-mousepad/releases/download/v#{version}/Mousepad.zip"
  name "Mousepad"
  desc "Text editor modelled on Xfce Mousepad"
  homepage "https://github.com/code-zenx/homebrew-mousepad"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Mousepad.app"

  # The app is ad-hoc signed, not Developer ID signed + notarized, so Gatekeeper
  # rejects it once Homebrew stamps the download with com.apple.quarantine.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Mousepad.app"],
        writable_paths: ["Mousepad.app"],
        writable_base:  :appdir
  end

  zap trash: [
    "~/Library/Preferences/dev.siddharth.mousepad.plist",
    "~/Library/Saved Application State/dev.siddharth.mousepad.savedState",
  ]
end
