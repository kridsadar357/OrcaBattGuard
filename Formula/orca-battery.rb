class OrcaBattery < Formula
  desc "Read-only CLI for Orca Battery Guardian"
  homepage "https://github.com/kridsadar357/OrcaBattGuard"
  url "https://github.com/kridsadar357/OrcaBattGuard/archive/refs/tags/v0.8.0.tar.gz"
  sha256 "89a842bb23adf831ef0752f011c23f2d77c4d5ca1ab93023c8f5a46261f188e4"
  head "https://github.com/kridsadar357/OrcaBattGuard.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "orca-battery"
    libexec.install ".build/release/orca-battery" => "orca"
    libexec.install ".build/release/OrcaBatteryGuardian_OrcaBatteryGuardian.bundle"
    bin.write_exec_script libexec/"orca"
    bin.install_symlink "orca" => "orca-battery"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/orca version")
    assert_match "Orca Battery Guardian CLI", shell_output("#{bin}/orca help")
    assert_match "Battery:", shell_output("#{bin}/orca status")
  end
end
