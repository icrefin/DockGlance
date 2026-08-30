cask "dockglance" do
  version "2.0.1"
  sha256 "34630b678388562e11acb1068b46057d9451921b54137e942c710b90a11b869e"

  url "https://github.com/icrefin/DockGlance/releases/download/v#{version}/DockGlance-#{version}.zip"

  name "DockGlance"
  desc "Dock-side system metrics widget: CPU, memory, temperature, network, clock, weather"
  homepage "https://github.com/icrefin/DockGlance"

  app "DockGlance.app"
end
