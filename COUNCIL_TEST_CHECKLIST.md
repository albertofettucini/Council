# Council — Test Kontrol Listesi

> **Historical.** A manual pass written against a pre-1.0 build — several screens it walks through
> (the project-name setup screen, the old stage navigation) no longer exist, and nothing added since
> v1.0 is covered. Kept as a record of how the app was hand-tested at the time.

> Test ederken kutucukları işaretle. **⚠ işaretliler = bu turda düzelttiğim ince bug'lar**, onlara özellikle bak.

## 0. Hazırlık
- [ ] En az 2 gerçek API key hazır (Claude / Gemini / GPT)

## 1. İlk açılış / Proje
- [ ] (İlk kez) Proje adı ekranı çıkıyor, max 5 karakter, INITIALIZE → ana ekran
- [ ] Sol üstte `PROJECT_ADI` görünüyor
- [ ] Sol üstteki 🔴🟡🟢 düğmeleri yazıya binmiyor (zaten onayladın)

## 2. API Key + Model
- [ ] Panele key yapıştır → Enter → VALIDATING → geçerliyse model seçimi gelir
- [ ] Key ekranda `••••` maskeli, **"Passwords" popup'ı ÇIKMIYOR**
- [ ] Geçersiz key → kırmızı hata, kaydetmiyor
- [ ] Model seç → BEGIN → "Awaiting directive"
- [ ] Panel başlığında model adı yazıyor + küçük menüden değiştirilebiliyor
- [ ] Anahtar (🗝) ikonu → key'i kaldırıyor

## 3. Soru sorma (Roundtable)
- [ ] Soru yaz → EXECUTE (veya Enter) → bağlı modeller **paralel** cevap, token token akıyor
- [ ] Akarken metnin sonunda **yanıp sönen imleç** var
- [ ] Shift+Enter satır atlıyor, Enter gönderiyor
- [ ] 📷 / sürükle-bırak / ⌘V ile görsel ekleniyor, görselle soru gidiyor
- [ ] Sadece görsel (boş metin) → yine cevap geliyor

## 4. Durdur / Yeniden üret / Retry
- [ ] Üretim sırasında buton STOP (kırmızı) → basınca duruyor, yarım cevap ekranda kalıyor
- [ ] Panel üstüne gel (hover) → REGEN → o model yeniden üretiyor
- [ ] Hata veren panelde kırmızı RETRY → tekrar deniyor
- [ ] ⚠ Soru sor → ortada STOP → **yeni** soru sor → ikinci cevap mantıklı (yarım metne takılmıyor)

## 5. Turlar (Round)
- [ ] Yeni soru → yeni tur oluşuyor. `‹ ›` (veya ⌘[ ⌘]) ile turlar arası gez
- [ ] Eski tura bakınca o turun cevap + analizleri duruyor, bozulmuyor

## 6. Peer Review
- [ ] Sidebar → PEER REVIEW → modeller birbirini eleştiriyor, panelde "PEER REVIEW" başlığı altında
- [ ] Metinde **gerçek isimler** ("Gemini'ye katılmıyorum" gibi), "Advisor B" değil
- [ ] Tekrar bas → yeniden üretmiyor, mevcudu gösteriyor
- [ ] ⚠ Peer review yap → bir modeli REGEN et → tüm peer review temizleniyor (bayat kalmıyor)

## 7. Divergence
- [ ] Sidebar → DIVERGENCE → tam ekran, "Agreement / Divergence" haritası, GENERATE ile üretiyor
- [ ] Başlıkta `· via MODEL` yazıyor
- [ ] ≥2 cevap yokken GENERATE kapalı + doğru sebep yazıyor
- [ ] ⚠ (Mümkünse interneti kıs) başarısız olursa → kırmızı `⚠︎ hata` çıkıyor ama **kalıcı kaydolmuyor** (kapat-aç → temiz)

## 8. Synthesis
- [ ] Sidebar → SYNTHESIS → nihai öneri + "Where they diverged" bölümü (muhalefet korunuyor)
- [ ] Ayarlardan synthesizer modeli değiştirilebiliyor

## 9. Ayarlar (⌘,)
- [ ] PROJECT → ad değiştir → sidebar anında güncelleniyor
- [ ] APPEARANCE → Dark/Light, seçilide ışık huzmesi sabit
- [ ] SYSTEM PROMPT (genel) + PER-MODEL
- [ ] SAMPLING → temperature slider + max tokens, ⟲ ile AUTO'ya dönüyor
- [ ] DIVERGENCE & SYNTHESIS MODEL seçimi
- [ ] CONVERSATION STORAGE → "Reveal in Finder" çalışıyor
- [ ] ⎋ (Escape) ile kapanıyor

## 10. History (sol panel)
- [ ] Geçmiş sohbetler listeleniyor, tıkla → açılıyor
- [ ] Sağ tık → Rename / Delete
- [ ] 3+ sohbette arama kutusu çıkıyor, çalışıyor
- [ ] Boşken "No saved directives yet" yazıyor
- [ ] ⚠ Üretim sürerken history + NEW DIRECTIVE **kilitli** (tıklanmıyor, soluk)

## 11. Export
- [ ] roundNavigator'da EXPORT (veya ⌘E) → Copy markdown / Save .md / Save PDF

## 12. Kalıcılık + Dark
- [ ] Uygulamayı kapat-aç → son sohbet geri geliyor, key'ler Keychain'de duruyor
- [ ] Dark mode'da her yüzey düzgün görünüyor (sidebar, panel, ayarlar, export menü)
