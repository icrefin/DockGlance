cask "dockglance" do
  version "2.0.1"
  sha256 "e39b3b492c0ee255501faffd4faf2386a075feaf8c990c75349f93c76d7f74c9"

  url "https://github.com/icrefin/DockGlance/releases/download/v#{version}/DockGlance-#{version}.zip"

  name "DockGlance"
  desc "Dock-side system metrics widget: CPU, memory, temperature, network, clock, weather"
  homepage "https://github.com/icrefin/DockGlance"

  app "DockGlance.app"
end
