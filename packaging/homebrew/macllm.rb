# Homebrew Cask — MacLLM 1.8.0
# Kurulum: brew install --cask ./packaging/homebrew/macllm.rb

cask "macllm" do
  version "1.8.0"
  sha256 "979789bb00b392e8a9db5b8ffec19e45308cab3471e02de50319fd44bfd30975"

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
