# Homebrew

## Cask ile kurulum (release DMG’sinden)

Release indirildikten sonra, repoda güncel cask dosyasıyla:

```bash
brew install --cask ./packaging/homebrew/macllm.rb
```

## Doğrudan release URL (cask dosyası olmadan)

```bash
brew install --cask https://raw.githubusercontent.com/kuarezma/MacLLM/main/packaging/homebrew/macllm.rb
```

> `main` üzerindeki cask her release ile güncellenir; sürümünüzle uyumlu olduğundan emin olun.

## Güncelleme

```bash
brew upgrade --cask macllm
```
