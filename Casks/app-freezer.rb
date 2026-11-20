cask "app-freezer" do
  # version and sha256 are updated by .github/workflows/release.yml on each release.
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/yurishevtsov/app-freezer/releases/download/v#{version}/AppFreezer.zip"
  name "AppFreezer"
  desc "Pause and resume running apps to simulate a frozen app"
  homepage "https://github.com/yurishevtsov/app-freezer"

  depends_on macos: ">= :sonoma"

  app "AppFreezer.app"

  # The app is ad-hoc signed, not notarized. Clear the quarantine flag so
  # Gatekeeper lets it open.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/AppFreezer.app"]
  end

  # Quitting AppFreezer resumes every app it froze.
  uninstall quit: "io.github.yurishevtsov.appfreezer"

  zap trash: [
    "~/Library/Preferences/io.github.yurishevtsov.appfreezer.plist",
    "~/Library/Saved Application State/io.github.yurishevtsov.appfreezer.savedState",
  ]
end
