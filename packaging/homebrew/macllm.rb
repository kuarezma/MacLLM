# Homebrew Cask — MacLLM 1.14.27
# Kurulum: brew install --cask ./packaging/homebrew/macllm.rb

cask "macllm" do
  version "1.14.27"
  sha256 "c4aea300b42c96f8d9c8aee815a17f15890f044ff957bf27433dbb63e44afefe"

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
