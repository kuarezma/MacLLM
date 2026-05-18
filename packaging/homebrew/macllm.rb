# Homebrew Cask — MacLLM 1.5.1
# Kurulum: brew install --cask ./packaging/homebrew/macllm.rb

cask "macllm" do
  version "1.5.1"
  sha256 "7bd33349b7fdde693edd8fa9f3c0ac516fecd4d8588e40cc06d8670d0cdf9121"

  url "https://github.com/kuarezma/MacLLM/releases/download/v\#{version}/MacLLM-\#{version}-macOS-arm64.dmg"
  name "MacLLM"
  desc "Native local LLM chat for Apple Silicon (Metal, Hugging Face GGUF)"
  homepage "https://github.com/kuarezma/MacLLM"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "MacLLM.app"

  zap trash: [
    "~/Library/Application Support/MacLLM",
  ]
end
