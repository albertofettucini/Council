# COUNCIL — Build Log

> **Historical.** This log stops at the pre-1.0 build. Divergence, synthesis, persistent history,
> the devil's-advocate seat, the decision journal, the guest seat and the neutral chair have all
> shipped since — and the engine has moved out into the CouncilKit package, so the file tree below
> no longer matches the repo. Kept as a build diary, not a status report; see the README for what
> is actually live.

Native macOS (SwiftUI) uygulaması. Bu dosya, Council üzerinde yaptığımız çalışmanın kaydıdır.
_Konum: proje kökü (`Council/COUNCIL_BUILD_LOG.md`) — Xcode synced source klasörünün dışında, build'e dahil değil._

---

## 1. Council nedir (vizyon / north star)

Zor soruları **düşünmek** için bir araç. Tek bir AI'dan tek kendinden-emin cevap yerine, farklı
AI zihinlerini (Claude / Gemini / GPT) bir yuvarlak masada toplar; paralel cevap verir, birbirinin
muhakemesini inceler, nerede anlaşıp nerede ayrıştıklarını yüzeye çıkarır.

**Ürün cevap değil — ürün müzakerenin (deliberation) kendisi. İnsan karar verici kalır.**

### 6 çekirdek ilke
1. **Deliberation > answers** — değer yapılandırılmış anlaşmazlık + dürüst sentezde.
2. **Transparency > authority** — nerede ayrıştıkları HER ZAMAN gösterilir; muhalefet gömülmez. "See the dissent, not just the decision."
3. **İnsan karar verir** — Council yargıyı besler, yerine geçmez.
4. **Limitler konusunda dürüst** — debate sihirli şekilde doğru üretmez; anonim peer review, devil's-advocate gibi mekanizmalarla buna karşı mühendislik yapılır; "debate = better" diye overclaim edilmez.
5. **Gizlilik & sahiplik** — BYO keys, macOS Keychain'de. Açık kaynak. Senin verin, anahtarın, makinen.
6. **Deneyim de amacın parçası** — törensel ama her şeyden önce TEMİZ/okunabilir; rakiplerin dağınık dashboard'larının kasıtlı zıttı.

### Council NE DEĞİL
Çok-modelli chat switcher değil · sadece yan-yana viewer değil · "AI'lar sohbet ediyor" oyuncağı değil · debate'in daha iyi cevap garantilediğini iddia eden araç değil.

---

## 2. Mimari / dosya yapısı

Xcode 16, SwiftUI, macOS 14+, Swift 5. Synced-root proje (`Council/Council/` klasörüne eklenen dosyalar otomatik target'a girer).

```
Council/
├─ Council.xcodeproj
├─ COUNCIL_BUILD_LOG.md            ← bu dosya
└─ Council/                        ← synced source root
   ├─ CouncilApp.swift             @main, WindowGroup → ContentView(store:)
   ├─ Models/
   │  ├─ Seat.swift                koltuk: id + archetype + provider + model (Codable, geriye-uyumlu)
   │  ├─ LLMProvider.swift         claude/openAI/gemini/foundationModels + defaultModel + modelOptions + keychainAccount
   │  └─ Archetype.swift           sage/scientist/strategist (şu an çağrılarda kullanılmıyor; nötr prompt)
   ├─ Services/
   │  ├─ LLMClient.swift           protocol + ChatMessage + ImageAttachment + KeyValidation + LLMClientFactory + UnavailableClient
   │  ├─ AnthropicClient.swift     /v1/messages (x-api-key, anthropic-version, system top-level)
   │  ├─ OpenAICompatibleClient.swift  /chat/completions (Bearer) — GPT + Gemini'nin OpenAI-uyumlu endpoint'i
   │  └─ KeychainStore.swift       save/read/delete (kSecClassGenericPassword)
   ├─ Persistence/
   │  └─ CouncilStore.swift        @Observable merkezi state (seats, transcripts, status, history, peerReviews)
   └─ Views/
      └─ ContentView.swift         tüm UI (sidebar + 3 panel + directive input + settings + onboarding)
```

### Build/çalıştırma kalıbı (stale-build'e karşı)
Xcode asset/cache yüzünden "ekrandaki ≠ son kod" sorunu yaşandığı için her seferinde:
```bash
killall Council
xcodebuild -project Council.xcodeproj -scheme Council -configuration Debug -destination 'platform=macOS' build
open <DerivedData>/Build/Products/Debug/Council.app
```

---

## 3. Güvenlik modeli (API key'ler)

- Key'ler **YALNIZCA macOS Keychain**'de (`KeychainStore`, account = `apikey.<provider>`).
- Ekranda **maskeli** — ama `NSSecureTextField` DEĞİL: macOS her secure field için "Passwords…" autofill popup'ı gösteriyor ve kapatan public API yok. Onun yerine **düz `NSTextField` + elle bullet maskeleme** (`MaskedKeyField`): alan sadece `•` gösterir, gerçek karakterler yalnızca bellekteki `@State`'te durur, Keychain'e verildikten sonra silinir.
  - Takas: OS "secure input" (tuş izolasyonu) kaybedildi. Lokal BYO-key app için kabul edilebilir; key hâlâ ekranda maskeli, log/UserDefaults'a ASLA gitmiyor.
- **Hiçbir yerde plaintext yok:** ekran maskeli · UserDefaults sadece seat config + proje adı (key ASLA) · log yok (tek `print` Keychain DEBUG self-test'inde, sahte `hello-council-123` değeriyle, release'de yok).
- **Key doğrulama:** key girilince önce 1-token'lık küçük bir test çağrısı (`validate`) yapılır. Geçerliyse kaydedilir, geçersiz/bakiyesizse kaydedilmez + kullanıcıya net mesaj.

---

## 4. Yapılanlar (kronolojik)

### Foundation / UI iskeleti
- **Transcript-accumulation modeli:** sohbet sıfırlanmıyor; her cevap alta ekleniyor, başında `-`, aralarda boş satır, otomatik en alta kayma.
- **Light "blueprint/brutalist" estetik:** beyaz zemin, siyah ince/kalın çizgiler, grid arka plan, serif başlık + monospace detay.
- **Proje adı onboarding:** ilk açılışta max 5 harf → sol üstte `PROJECT_XXXXX`.
- **Cevap akışında küçülme:** input atılınca (cevap gelmeye başlayınca) üst başlık + alt status küçülüyor, içerik öne çıkıyor.

### Güvenlik
- Maskeli key alanı (önce `NSSecureTextField`, sonra popup yüzünden `MaskedKeyField`'e geçildi).
- **"Passwords…" popup'ı** iki kaynaktan geliyordu: (1) onboarding'de auto-focus edilen düz alan → AppKit `PlainTextField` + auto-focus kaldırıldı; (2) key alanındaki secure field → `MaskedKeyField`. İkisi de çözüldü.
- ⌘V ile **görsel yapıştırma**: `performKeyEquivalent` ile ⌘V yakalanıyor, panoda resim varsa alınıyor, yoksa normal metin paste.

### Dark mode + Settings
- `Blue` paleti adaptive yapıldı (`Color.adaptive(light:dark:)` + `NSColor` dynamic provider). Tüm renkler tek tuşla dönüyor.
- **Varsayılan light**, dark seçeneği **Settings** sheet'inde (sağ üstte dişli yoktu → sol menü SETTINGS'ten). Ana ekran minimal kalsın diye toggle sadece ayarlarda.
- Light/Dark seçeneği **kutusuz, yukarıdan ışık huzmesiyle** aydınlanıyor. Huzme seçili VEYA hover edilende görünür (hover preview; cursor çekilince söner, seçili kalan parlak kalır).

### Sol menü (deliberation modları)
- `STRATEGY/CREATIVE/ANALYTICS` (persona gibi okunan, işlevsiz) → **müzakere modlarına** çevrildi: `ROUND 1` (aktif), `PEER REVIEW`, `DIVERGENCE`, `SYNTHESIS`.
- Yapılmayanlar **kilitli** (soluk + kilit ikonu + tooltip) — "yapmayan buton" göstermemek için dürüst.
- `LOGOUT` kaldırıldı (hesap yok). `SETTINGS` aktif (sheet açıyor).
- **Kavram netleşti:** sol menü = *nasıl* müzakere ettikleri (süreç), paneller = *kim* (Claude/Gemini/GPT).

### Panelin sadeleşmesi (jargon temizliği)
- Çizilen marka sembolleri (Claude sunburst / Gemini sparkle / GPT rosette) önce eklendi, sonra **kaldırıldı** (Joseph istedi).
- `SYS.FOCUS:` öneki, `ADVISOR_ID`, model picker'daki "ENTER MODEL ID" serbest-metin alanı, footer (`NEURAL_ARCHITECT` + `BYO_KEYS…`), `v1.0_BUILD` → hepsi kaldırıldı.
- **Üstteki COUNCIL başlık çubuğu komple kaldırıldı.** Panel-aç/kapat kontrolü en soldaki dikey çizgiye entegre edildi (chevron, 180° dönüyor — sembol değişmediği için imleç flicker'ı yok).
- Panel içerikleri (key girişi / awaiting / model seçimi) **dikey+yatay ortalandı**; başlık çizgisiyle arasına nefes payı (18px) kondu.

### Model seçimi
- `Seat.model` eklendi (Codable geriye-uyumlu `init(from:)` ile — eski kayıtlar `provider.defaultModel`'e düşer, veri silinmez).
- `LLMProvider.modelOptions` (öneri listesi). `LLMClientFactory.make(for:model:)` artık seçilen modeli kullanıyor.
- Akış: key girilip **doğrulanınca** o panelde **model seçimi** çıkıyor → seçim + sağ altta **BEGIN →**. BEGIN'e basınca panel hazır. Returning kullanıcı (key zaten kayıtlı) seçim ekranını görmeden direkt hazır gelir (`justEnteredKey` gate'i).

### Görsel (vision) desteği
- `ImageAttachment` (PNG, base64) — foto butonu + **sürükle-bırak** + **⌘V**. Küçük thumbnail + "tıkla büyüt" (sheet).
- Üç sağlayıcının vision formatı: Anthropic `image` content bloğu, OpenAI/Gemini `image_url` data URL.
- Sandbox dosya izni zaten vardı (`ENABLE_USER_SELECTED_FILES = readonly`).

### Backend temeli (görünmez iş — tüm modların üstüne oturduğu katman)
- **Mesaj-listesi API'si:** `LLMClient.complete(messages: [ChatMessage], apiKey:)`. `ChatMessage` = role (system/user/assistant) + text + opsiyonel image. Tek-soru'dan **konuşma**ya geçiş — peer review'ın anahtarı.
- **Per-seat conversation history:** her koltuk kendi geçmişini taşıyor → takip soruları artık **bağlamlı** (önceden her çağrı sıfırdandı, model kendi cevabını bile görmüyordu).
- Tüm turlar tek primitive'den geçiyor: `answer(for:messages:)`.

### PEER REVIEW (Round 2) — ilk müzakere modu, CANLI
- Round 1 sonrası: her model diğerlerinin cevabını **anonim** okuyor ("Advisor A/B" — favori oynamasın diye), nerede katılıp ayrıldığını söylüyor, fikrini rafine ediyor/savunuyor.
- Prompt'ta açık talimat: **"sırf uyum olsun diye konsensüse boyun eğme"** (vizyonun "muhalefeti koru" ilkesi).
- İnceleme her panelin altına `PEER REVIEW` başlığıyla ekleniyor.
- Sidebar PEER REVIEW: ≥2 keyed+cevaplı koltuk varken ve hiçbir şey yüklenmiyorken **aktif/tıklanır**; yoksa kilitli (tooltip: "Önce bir soru sor…").

### API key doğrulama + key silme
- `validate(apiKey:)` her client'ta (1-token test çağrısı). `KeyValidation.interpret(status:body:)` HTTP durumunu net mesaja çeviriyor: `API key geçersiz` / `Bakiye/kota yetersiz` / `Doğrulanamadı (HTTP …)`.
- `validateAndSaveKey` — sadece geçerliyse kaydeder. UI'da "DOĞRULANIYOR…" + sonuç.
- `clearKey` — panel başlığında (bağlıyken + sohbet yokken) küçük **key.slash** ikonu → key'i sil, yeniden gir.

---

## 5. Şu anki durum

**Çalışıyor (kullanılabilir):**
- ROUND 1 — 3 paralel cevap, BYO-key + Keychain + **key doğrulama**.
- Dark/Light tema, model seçimi (panel başına), görsel girişi (buton/drag/paste), bağlam-hafıza (multi-turn).
- **PEER REVIEW** — anonim Round 2, panel altına inceleme.
- Sol panel aç/kapat, proje adı onboarding, settings.

**Bekleyen (kilitli / yapılacak):**
- **DIVERGENCE** ve **SYNTHESIS** — tek birleşik çıktı oldukları için 3-kolon yerine **tam-genişlik bir görünüm** gerekiyor (tasarımı önce Joseph'e gösterilecek).
- Devil's-advocate koltuğu (vizyon).
- Geçmişin uygulama kapanınca kalıcı olması (şu an sıfırlanıyor).
- BEGIN sonrası model değiştirme (şimdilik key.slash ile dolaylı).
- Font bundling (Bodoni/Archivo/JetBrains), orphan dosya temizliği (eski SetupView vs.).

---

## 6. Dürüst notlar / kararlar
- **MaskedKeyField takası:** secure-input korumasından feragat edildi (popup'ı öldürmek için). Lokal app için kabul edilebilir.
- **Görsel geçmişte tekrar gönderilmiyor** (maliyet) — etkisi o cevaba zaten işlemiş oluyor.
- **Key doğrulama = 1 gerçek minik API çağrısı** (~1 token, ihmal edilebilir).
- **Persona vs model:** vizyon "persona + devil's-advocate" diyordu; pratiğte paneller provider-kimliğine (Claude/Gemini/GPT) geçti. İşlevsel-rol ileride uzlaştırılabilir.

---

## 7. Sıradaki adım
**DIVERGENCE + SYNTHESIS.** Backend primitive'leri hazır (mesaj-listesi + round runner). Eksik olan: tam-genişlik çıktı görünümünün tasarımı (kim üretir, nasıl gösterilir — "transparency > authority" + "preserve dissent" ilkeleriyle). Tasarım önce gösterilecek, sonra kodlanacak.
