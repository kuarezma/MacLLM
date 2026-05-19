# Homebrew Cask — MacLLM 1.14.14
# Kurulum: brew install --cask ./packaging/homebrew/macllm.rb

cask "macllm" do
  version "1.14.14"
  sha256 "fc46b7527e570a287f959ab6626438bae586d22a42270cd632c0eafdc6a56459"

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
