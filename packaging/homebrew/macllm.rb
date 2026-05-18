# Homebrew Cask — MacLLM 1.4.2
# Kurulum: brew install --cask ./packaging/homebrew/macllm.rb

cask "macllm" do
  version "1.4.2"
  sha256 "457619b972ca255b23fcb5d9d9bf85ac07cf3e64339a8709b5e6eb10916a03ec"

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
