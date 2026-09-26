/* Avrupa Kurumsal Bulten - arayuz mantigi
   Veri: data/haberler.js (Tara.ps1 uretir) -> window.HABER_VERISI
   Kullanici tercihleri (okundu / kaydedildi / tema) localStorage'da tutulur. */

(function () {
  'use strict';

  var SAYFA_ADIM = 60;

  // ------------------------------------------------------------ depolama
  var D = {
    oku: function (anahtar, varsayilan) {
      try {
        var v = localStorage.getItem('ht.' + anahtar);
        return v === null ? varsayilan : JSON.parse(v);
      } catch (e) { return varsayilan; }
    },
    yaz: function (anahtar, deger) {
      try { localStorage.setItem('ht.' + anahtar, JSON.stringify(deger)); } catch (e) { /* kota dolu */ }
    }
  };

  var okunan = D.oku('okunan', {});
  var kayitli = D.oku('kayitli', {});
  var oncekiZiyaret = D.oku('sonZiyaret', '');
  D.yaz('sonZiyaret', new Date().toISOString().slice(0, 19));

  if (D.oku('tema', '') === 'koyu') { document.body.classList.add('koyu'); }

  // ------------------------------------------------------------- durum
  var durum = {
    gorunum: 'tumu',      // tumu | okunmamis | kayitli
    grup: 'tumu',
    firma: '',
    arama: '',
    gun: 0,               // 0 = baslangic tarihinden bu yana
    tekGun: '',           // zaman serisinden secilen gun (YYYY-MM-DD)
    sira: 'yeni',
    sadeceOkunmamis: false,
    siniflandirilmamisGoster: false,
    limit: SAYFA_ADIM
  };

  var veri = window.HABER_VERISI || { meta: {}, gruplar: [], haberler: [] };
  var grupHarita = {};

  var el = {};
  ['ust', 'ustOzet', 'arama', 'aramaSatiri', 'btnAra', 'btnAramaKapat', 'btnYenile', 'btnTema',
   'konuSerit', 'tarihSerit', 'siraSerit', 'hizliMenu', 'grupMenu', 'firmaMenu', 'firmaArama',
   'firmaGrupAdi', 'sadeceOkunmamis', 'sinifsizGoster', 'btnHepsiOkundu', 'btnDisaAktar',
   'zamanSerisi', 'filtreOzet', 'liste', 'dahaFazlaSarma', 'yanPanel', 'panelPerde',
   'btnPanelKapat', 'altNav', 'navOkunmamis', 'btnYukari'].forEach(function (k) {
    el[k] = document.getElementById(k);
  });
  var yanPanel = el.yanPanel;

  var TARIH_SECENEK = [
    { d: 0,  ad: 'Tümü' }, { d: 1, ad: 'Bugün' }, { d: 2, ad: '2 gün' },
    { d: 7,  ad: '7 gün' }, { d: 30, ad: '30 gün' }
  ];
  var SIRA_SECENEK = [
    { d: 'yeni', ad: 'En yeni' }, { d: 'eski', ad: 'En eski' }, { d: 'kaynak', ad: 'Kaynak' }
  ];

  // ------------------------------------------------------------ yardimcilar
  function kacis(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function tarihNesnesi(s) { return new Date(String(s).replace(' ', 'T')); }

  function gunAnahtari(d) {
    return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
  }

  var AYLAR = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
               'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  var GUNLER = ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'];

  function gunEtiketi(anahtar) {
    var bugun = gunAnahtari(new Date());
    var dun = gunAnahtari(new Date(Date.now() - 86400000));
    if (anahtar === bugun) { return 'Bugün'; }
    if (anahtar === dun) { return 'Dün'; }
    var p = anahtar.split('-');
    var d = new Date(+p[0], +p[1] - 1, +p[2]);
    return d.getDate() + ' ' + AYLAR[d.getMonth()] + ' ' + d.getFullYear() + ', ' + GUNLER[d.getDay()];
  }

  function saatEtiketi(d) {
    return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
  }

  // Ticari unvani ekranda okunur hale getirir:
  // "KAPTAN DEMIR CELIK ENDUSTRISI VE TICARET ANONIM SIRKETI" -> "Kaptan Demir Çelik"
  var HUKUKI = /\s+(ANON[İI]M|L[İI]M[İI]TED|Ş[İI]RKET[İI]?|A\.?Ş\.?|LTD\.?|ŞT[İI]\.?|SAN\.?|T[İI]C\.?|SANAY[İI][İI]?|T[İI]CARET[İI]?|VE)\b.*$/i;

  function kisaAd(unvan) {
    var s = String(unvan || '').replace(HUKUKI, '').trim();
    if (s.length < 3) { s = String(unvan || '').trim(); }
    if (s.length > 42) { s = s.slice(0, 40).trim() + '…'; }
    // TAMAMI BUYUK yazilmis unvanlari Baslik Bicimine cevir
    if (s === s.toLocaleUpperCase('tr')) {
      s = s.toLocaleLowerCase('tr').replace(/(^|[\s\-\.\/])(\S)/g, function (t, a, b) {
        return a + b.toLocaleUpperCase('tr');
      });
    }
    return s;
  }

  // Turkce karakterleri sadelestirir; aramada "Türk" ile "turk" ayni sayilir.
  function duzle(s) {
    return String(s == null ? '' : s)
      .replace(/[İIı]/g, 'i').replace(/[Şş]/g, 's').replace(/[Ğğ]/g, 'g')
      .replace(/[Üü]/g, 'u').replace(/[Öö]/g, 'o').replace(/[Çç]/g, 'c')
      .toLowerCase();
  }

  // -------------------------------------------------------------- filtreler
  // Sadece tarih filtresi uygulanmis liste; grup/firma sayaclari bunun uzerinden
  // hesaplanir, boylece bir grubu secince digerlerinin sayisi degismez.
  function tarihSuzulmus() {
    var alt = null;
    if (durum.tekGun) {
      return veri.haberler.filter(function (h) { return gunAnahtari(tarihNesnesi(h.tarih)) === durum.tekGun; });
    }
    if (durum.gun > 0) {
      alt = new Date();
      alt.setHours(0, 0, 0, 0);
      alt.setDate(alt.getDate() - (durum.gun - 1));
      var t = alt.getTime();
      return veri.haberler.filter(function (h) { return tarihNesnesi(h.tarih).getTime() >= t; });
    }
    return veri.haberler.slice();
  }

  function suzulmus() {
    var liste = tarihSuzulmus();
    var q = duzle(durum.arama).trim();

    liste = liste.filter(function (h) {
      if (durum.gorunum === 'kayitli' && !kayitli[h.id]) { return false; }
      if (durum.gorunum === 'okunmamis' && okunan[h.id]) { return false; }
      if (durum.sadeceOkunmamis && okunan[h.id]) { return false; }
      // Hicbir konuya girmeyen haberler varsayilan olarak gizli
      if (durum.gorunum === 'siniflandirilmamis') {
        if (h.gruplar.length !== 0) { return false; }
      } else if (h.gruplar.length === 0 && !durum.siniflandirilmamisGoster) {
        return false;
      }
      if (durum.grup !== 'tumu' && h.gruplar.indexOf(durum.grup) === -1) { return false; }
      if (durum.firma && h.firmalar.indexOf(durum.firma) === -1) { return false; }
      if (q) {
        var metin = duzle(h.baslik + ' ' + h.kaynak + ' ' + h.firmalar.join(' '));
        var kelimeler = q.split(/\s+/);
        for (var i = 0; i < kelimeler.length; i++) {
          if (metin.indexOf(kelimeler[i]) === -1) { return false; }
        }
      }
      return true;
    });

    liste.sort(function (a, b) {
      if (durum.sira === 'kaynak') {
        var k = duzle(a.kaynak).localeCompare(duzle(b.kaynak));
        if (k !== 0) { return k; }
      }
      var fa = tarihNesnesi(a.tarih).getTime(), fb = tarihNesnesi(b.tarih).getTime();
      return durum.sira === 'eski' ? fa - fb : fb - fa;
    });

    return liste;
  }

  function yeniMi(h) { return oncekiZiyaret && h.eklendi > oncekiZiyaret; }

  // ---------------------------------------------------------------- cipler
  // Acilir liste yerine yatay kaydirilan etiketler; dokunmatikte cok daha rahat.
  function cipYap(secili, etiket, sayi, renk, tiklama) {
    var b = document.createElement('button');
    b.className = 'cip' + (secili ? ' aktif' : '');
    if (renk) {
      var n = document.createElement('span');
      n.className = 'nokta'; n.style.background = renk;
      b.appendChild(n);
    }
    b.appendChild(document.createTextNode(etiket));
    if (sayi !== '' && sayi !== undefined && sayi !== null) {
      var s = document.createElement('span');
      s.className = 'sayi'; s.textContent = sayi;
      b.appendChild(s);
    }
    b.addEventListener('click', tiklama);
    return b;
  }

  function panelAc(ac) {
    if (!yanPanel) { return; }
    yanPanel.classList.toggle('acik', ac);
    el.panelPerde.classList.toggle('acik', ac);
    document.body.classList.toggle('kilitli', ac && window.innerWidth <= 1000);
  }

  function altNavIsaretle() {
    if (!el.altNav) { return; }
    var d = el.altNav.querySelectorAll('button');
    for (var i = 0; i < d.length; i++) {
      var g = d[i].getAttribute('data-gorunum');
      d[i].classList.toggle('aktif', !!g && g === durum.gorunum);
    }
  }

  // ------------------------------------------------------------ ciz: menuler
  function menuDugmesi(secili, etiket, adet, renk, tiklama, rozet) {
    var b = document.createElement('button');
    if (secili) { b.className = 'aktif'; }
    if (renk) {
      var n = document.createElement('span');
      n.className = 'nokta'; n.style.background = renk;
      b.appendChild(n);
    }
    var a = document.createElement('span');
    a.className = 'ad'; a.textContent = etiket; b.appendChild(a);
    if (rozet) {
      var r = document.createElement('span');
      r.className = 'rozet'; r.textContent = rozet; b.appendChild(r);
    }
    var s = document.createElement('span');
    s.className = 'adet'; s.textContent = adet; b.appendChild(s);
    b.addEventListener('click', function () {
      tiklama();
      // Telefonda secim yapinca panel kapansin, sonuc gorunsun
      if (window.innerWidth <= 1000) { panelAc(false); }
    });
    return b;
  }

  function menuleriCiz() {
    var taban = tarihSuzulmus();

    var okunmamisSayi = 0, kayitliSayi = 0, yeniSayi = 0, konusuzSayi = 0, konuluSayi = 0;
    var grupSayac = {}, firmaSayac = {};
    taban.forEach(function (h) {
      var konusuz = (h.gruplar.length === 0);
      if (konusuz) { konusuzSayi++; } else { konuluSayi++; }
      if (konusuz && !durum.siniflandirilmamisGoster) { return; }
      if (!okunan[h.id]) { okunmamisSayi++; }
      if (kayitli[h.id]) { kayitliSayi++; }
      if (yeniMi(h)) { yeniSayi++; }
      h.gruplar.forEach(function (g) { grupSayac[g] = (grupSayac[g] || 0) + 1; });
      h.firmalar.forEach(function (f) { firmaSayac[f] = (firmaSayac[f] || 0) + 1; });
    });
    var anaSayi = durum.siniflandirilmamisGoster ? taban.length : konuluSayi;

    // hizli menu
    el.hizliMenu.innerHTML = '';
    el.hizliMenu.appendChild(menuDugmesi(durum.gorunum === 'tumu', 'Tüm haberler', anaSayi, '',
      function () { durum.gorunum = 'tumu'; yenidenCiz(); }, yeniSayi ? yeniSayi + ' yeni' : ''));
    el.hizliMenu.appendChild(menuDugmesi(durum.gorunum === 'okunmamis', 'Okunmamış', okunmamisSayi, '',
      function () { durum.gorunum = 'okunmamis'; yenidenCiz(); }));
    el.hizliMenu.appendChild(menuDugmesi(durum.gorunum === 'kayitli', 'Kaydedilenler', kayitliSayi, '',
      function () { durum.gorunum = 'kayitli'; yenidenCiz(); }));
    if (konusuzSayi) {
      el.hizliMenu.appendChild(menuDugmesi(durum.gorunum === 'siniflandirilmamis',
        'Sınıflandırılmamış', konusuzSayi, '',
        function () { durum.gorunum = 'siniflandirilmamis'; yenidenCiz(); }));
    }

    // konu menusu (yan panel)
    el.grupMenu.innerHTML = '';
    el.grupMenu.appendChild(menuDugmesi(durum.grup === 'tumu', 'Tüm konular', anaSayi, '#9aa3b0',
      function () { durum.grup = 'tumu'; yenidenCiz(); }));
    veri.gruplar.forEach(function (g) {
      el.grupMenu.appendChild(menuDugmesi(durum.grup === g.id, g.ad, grupSayac[g.id] || 0, g.renk,
        function () { durum.grup = g.id; yenidenCiz(); }));
    });

    // konu seridi (ust bar) - sadece haberi olan konular, coktan aza
    el.konuSerit.innerHTML = '';
    el.konuSerit.appendChild(cipYap(durum.grup === 'tumu', 'Tümü', anaSayi, '',
      function () { durum.grup = 'tumu'; yenidenCiz(); }));
    veri.gruplar.slice()
      .filter(function (g) { return grupSayac[g.id] || durum.grup === g.id; })
      .sort(function (a, b) { return (grupSayac[b.id] || 0) - (grupSayac[a.id] || 0); })
      .forEach(function (g) {
        el.konuSerit.appendChild(cipYap(durum.grup === g.id, g.ad, grupSayac[g.id] || 0, g.renk,
          function () { durum.grup = g.id; yenidenCiz(); }));
      });

    // zaman araligi ve siralama secimleri
    el.tarihSerit.innerHTML = '';
    TARIH_SECENEK.forEach(function (t) {
      el.tarihSerit.appendChild(cipYap(!durum.tekGun && durum.gun === t.d, t.ad, '', '',
        function () { durum.gun = t.d; durum.tekGun = ''; yenidenCiz(); }));
    });
    el.siraSerit.innerHTML = '';
    SIRA_SECENEK.forEach(function (s) {
      el.siraSerit.appendChild(cipYap(durum.sira === s.d, s.ad, '', '',
        function () { durum.sira = s.d; yenidenCiz(); }));
    });

    if (el.navOkunmamis) {
      el.navOkunmamis.textContent = okunmamisSayi > 0 ? (okunmamisSayi > 99 ? '99+' : okunmamisSayi) : '';
    }
    altNavIsaretle();

    // musteri menusu - haberi olanlar once, sonra digerleri
    el.firmaGrupAdi.textContent = '(' + (veri.musteriler || []).length + ')';
    var firmalar = (veri.musteriler || []).slice();
    var fq = duzle(el.firmaArama.value).trim();
    if (fq) {
      firmalar = firmalar.filter(function (f) { return duzle(f).indexOf(fq) !== -1 || duzle(kisaAd(f)).indexOf(fq) !== -1; });
    } else {
      firmalar = firmalar.filter(function (f) { return firmaSayac[f]; });
    }
    firmalar.sort(function (a, b) {
      var f = (firmaSayac[b] || 0) - (firmaSayac[a] || 0);
      return f !== 0 ? f : kisaAd(a).localeCompare(kisaAd(b), 'tr');
    });

    el.firmaMenu.innerHTML = '';
    if (durum.firma) {
      el.firmaMenu.appendChild(menuDugmesi(false, '← Müşteri filtresini kaldır', '', '',
        function () { durum.firma = ''; yenidenCiz(); }));
    }
    if (!firmalar.length) {
      var bos = document.createElement('div');
      bos.className = 'menu-bos';
      bos.textContent = fq ? 'Eşleşen müşteri yok' : 'Bu aralıkta haberi olan müşteri yok — aramayla tümüne ulaşabilirsin.';
      el.firmaMenu.appendChild(bos);
    }
    firmalar.slice(0, 200).forEach(function (f) {
      var d = menuDugmesi(durum.firma === f, kisaAd(f), firmaSayac[f] || 0, '',
        function () { durum.firma = f; yenidenCiz(); });
      d.title = f;
      el.firmaMenu.appendChild(d);
    });
  }

  // ------------------------------------------------------- ciz: zaman serisi
  function zamanSerisiCiz() {
    var gunSayisi = 45;
    var sayac = {}, sira = [];
    var d = new Date(); d.setHours(0, 0, 0, 0);
    for (var i = gunSayisi - 1; i >= 0; i--) {
      var t = new Date(d.getTime() - i * 86400000);
      var a = gunAnahtari(t);
      sayac[a] = 0; sira.push(a);
    }
    var enErken = veri.meta.baslangicTarihi || '';
    veri.haberler.forEach(function (h) {
      var a = gunAnahtari(tarihNesnesi(h.tarih));
      if (sayac[a] !== undefined) { sayac[a]++; }
    });
    var enYuksek = 1;
    sira.forEach(function (a) { if (sayac[a] > enYuksek) { enYuksek = sayac[a]; } });

    el.zamanSerisi.innerHTML = '';
    if (!veri.haberler.length) {
      var b = document.createElement('div');
      b.className = 'bos';
      b.textContent = 'Henüz veri yok — ilk taramadan sonra günlük haber yoğunluğu burada görünecek.';
      el.zamanSerisi.appendChild(b);
      return;
    }
    sira.forEach(function (a) {
      var c = document.createElement('div');
      c.className = 'cubuk';
      c.style.height = Math.max(3, Math.round(sayac[a] / enYuksek * 30)) + 'px';
      if (durum.tekGun === a) { c.style.opacity = '1'; }
      if (a < enErken) { c.style.opacity = '.12'; }
      c.title = gunEtiketi(a) + ' · ' + sayac[a] + ' haber';
      c.addEventListener('click', function () {
        durum.tekGun = (durum.tekGun === a) ? '' : a;
        yenidenCiz();
      });
      el.zamanSerisi.appendChild(c);
    });
  }

  // ------------------------------------------------------------- okuyucu
  // Haber uygulamanin icinde okunur; kaynak her zaman belirtilir ve
  // "kaynağında aç" bağlantısı korunur.
  var sonListe = [];
  var okuyucu = null;

  function okuyucuKur() {
    if (okuyucu) { return okuyucu; }
    var k = document.createElement('div');
    k.className = 'okuyucu-perde';
    k.innerHTML =
      '<div class="okuyucu" role="dialog" aria-modal="true">' +
        '<div class="okuyucu-bar">' +
          '<div class="okuyucu-kaynak"></div>' +
          '<div class="okuyucu-dugmeler">' +
            '<button class="ikon" data-rol="onceki" title="Önceki haber (←)">‹</button>' +
            '<button class="ikon" data-rol="sonraki" title="Sonraki haber (→)">›</button>' +
            '<button class="ikon" data-rol="yildiz" title="Kaydet">★</button>' +
            '<button class="ikon" data-rol="kapat" title="Kapat (Esc)">✕</button>' +
          '</div>' +
        '</div>' +
        '<div class="okuyucu-govde"></div>' +
      '</div>';
    document.body.appendChild(k);

    k.addEventListener('click', function (e) { if (e.target === k) { okuyucuKapat(); } });
    k.querySelector('[data-rol="kapat"]').addEventListener('click', okuyucuKapat);
    k.querySelector('[data-rol="onceki"]').addEventListener('click', function () { okuyucuKaydir(-1); });
    k.querySelector('[data-rol="sonraki"]').addEventListener('click', function () { okuyucuKaydir(1); });
    k.querySelector('[data-rol="yildiz"]').addEventListener('click', function () {
      var h = sonListe[okuyucu.sira];
      if (!h) { return; }
      if (kayitli[h.id]) { delete kayitli[h.id]; } else { kayitli[h.id] = 1; }
      D.yaz('kayitli', kayitli);
      okuyucuCiz();
    });

    okuyucu = k;
    okuyucu.sira = -1;
    return k;
  }

  function okuyucuAc(h) {
    okuyucuKur();
    okuyucu.sira = sonListe.indexOf(h);
    if (!okunan[h.id]) { okunan[h.id] = 1; D.yaz('okunan', okunan); }
    okuyucuCiz();
    okuyucu.classList.add('acik');
    document.body.classList.add('kilitli');
  }

  function okuyucuKapat() {
    if (!okuyucu) { return; }
    okuyucu.classList.remove('acik');
    document.body.classList.remove('kilitli');
    yenidenCiz(true);
  }

  function okuyucuKaydir(yon) {
    var y = okuyucu.sira + yon;
    if (y < 0 || y >= sonListe.length) { return; }
    okuyucu.sira = y;
    var h = sonListe[y];
    if (!okunan[h.id]) { okunan[h.id] = 1; D.yaz('okunan', okunan); }
    okuyucuCiz();
    okuyucu.querySelector('.okuyucu').scrollTop = 0;
  }

  function okuyucuCiz() {
    var h = sonListe[okuyucu.sira];
    if (!h) { return; }
    var d = tarihNesnesi(h.tarih);
    var grup = grupHarita[h.gruplar[0]];

    okuyucu.querySelector('.okuyucu-kaynak').innerHTML =
      '<span class="ok-kaynak-ad">' + kacis(h.kaynak || 'Kaynak belirtilmemiş') + '</span>' +
      '<span class="ok-kaynak-tarih">' + kacis(gunEtiketi(gunAnahtari(d)) + ' · ' + saatEtiketi(d)) + '</span>';

    okuyucu.querySelector('[data-rol="yildiz"]').className = 'ikon' + (kayitli[h.id] ? ' acik' : '');
    okuyucu.querySelector('[data-rol="onceki"]').disabled = (okuyucu.sira <= 0);
    okuyucu.querySelector('[data-rol="sonraki"]').disabled = (okuyucu.sira >= sonListe.length - 1);

    var etiketHtml = h.gruplar.map(function (gid) {
      var g = grupHarita[gid];
      return g ? '<span class="etiket grup" style="--konu:' + kacis(g.renk) + '">' + kacis(g.ad) + '</span>' : '';
    }).join('') + h.firmalar.map(function (f) {
      return '<span class="etiket" title="' + kacis(f) + '">' + kacis(kisaAd(f)) + '</span>';
    }).join('');

    var govde = '';
    govde += '<div class="etiketler ok-etiketler">' + etiketHtml + '</div>';
    govde += '<h2 class="ok-baslik">' + kacis(h.baslik) + '</h2>';

    if (h.gorsel) {
      govde += '<img class="ok-gorsel" src="' + kacis(h.gorsel) + '" alt="" ' +
               'onerror="this.style.display=\'none\'">';
    }

    if (h.metin) {
      govde += '<div class="ok-metin">' + h.metin.split('\n\n').map(function (p) {
        return '<p>' + kacis(p) + '</p>';
      }).join('') + '</div>';
    } else if (h.ozet) {
      govde += '<div class="ok-metin"><p>' + kacis(h.ozet) + '</p></div>';
      govde += '<div class="ok-uyari">Bu haberin tam metni alınamadı — yalnızca özeti gösteriliyor.</div>';
    } else if (h.durum === 'hata') {
      govde += '<div class="ok-uyari">Bu haberin metni alınamadı. Kaynak site otomatik erişime kapalı olabilir.</div>';
    } else {
      govde += '<div class="ok-uyari">Bu haberin içeriği henüz indirilmedi. <b>Icerik.ps1</b> çalıştığında burada görünecek.</div>';
    }

    var adres = h.gercekLink || h.link;
    govde += '<div class="ok-alt">' +
      '<div class="ok-atif">Kaynak: <b>' + kacis(h.kaynak || 'belirtilmemiş') + '</b>' +
      (h.gercekLink ? ' · ' + kacis(alanAdi(h.gercekLink)) : '') + '</div>' +
      '<a class="dugme sade kucuk" href="' + kacis(adres) + '" target="_blank" rel="noopener noreferrer">Kaynağında aç</a>' +
      '</div>';

    okuyucu.querySelector('.okuyucu-govde').innerHTML = govde;
  }

  function alanAdi(u) {
    try { return String(u).split('/')[2].replace(/^www\./, ''); } catch (e) { return ''; }
  }

  // -------------------------------------------------------------- ciz: liste
  function kartOlustur(h) {
    var grup = grupHarita[h.gruplar[0]];
    var d = tarihNesnesi(h.tarih);

    var kart = document.createElement('article');
    kart.className = 'kart' + (okunan[h.id] ? ' okundu' : '');

    var govde = document.createElement('div');
    govde.className = 'kart-govde';

    if (h.gorsel) {
      var sarma = document.createElement('div');
      sarma.className = 'kart-gorsel-sarma';
      var gorsel = document.createElement('img');
      gorsel.className = 'kart-gorsel';
      gorsel.src = h.gorsel; gorsel.alt = ''; gorsel.loading = 'lazy';
      gorsel.addEventListener('error', function () { sarma.remove(); });
      gorsel.addEventListener('click', function () { okuyucuAc(h); });
      sarma.appendChild(gorsel);
      govde.appendChild(sarma);
    }

    var icerik = document.createElement('div');
    icerik.className = 'kart-icerik';

    var ust = document.createElement('div');
    ust.className = 'kart-ust';
    var kaynak = document.createElement('span');
    kaynak.className = 'kaynak'; kaynak.textContent = h.kaynak || 'Kaynak belirtilmemiş';
    ust.appendChild(kaynak);
    var zaman = document.createElement('span');
    zaman.className = 'zaman'; zaman.textContent = saatEtiketi(d);
    ust.appendChild(zaman);
    if (yeniMi(h)) {
      var yr = document.createElement('span');
      yr.className = 'yeni-rozet'; yr.textContent = 'YENİ';
      ust.appendChild(yr);
    }

    // Islem dugmeleri meta satirinin sagina - kartin yanindaki dikey
    // sutun yerine burada durunca kart daha sade gorunuyor.
    var islem = document.createElement('div');
    islem.className = 'kart-islem';

    var kaydet = document.createElement('button');
    kaydet.className = 'ikon' + (kayitli[h.id] ? ' acik' : '');
    kaydet.textContent = kayitli[h.id] ? '★' : '☆';
    kaydet.title = kayitli[h.id] ? 'Kayıttan çıkar' : 'Kaydet';
    kaydet.addEventListener('click', function () {
      if (kayitli[h.id]) { delete kayitli[h.id]; } else { kayitli[h.id] = 1; }
      D.yaz('kayitli', kayitli);
      yenidenCiz(true);
    });
    islem.appendChild(kaydet);

    var okundu = document.createElement('button');
    okundu.className = 'ikon' + (okunan[h.id] ? ' acik' : '');
    okundu.textContent = okunan[h.id] ? '↺' : '✓';
    okundu.title = okunan[h.id] ? 'Okunmadı işaretle' : 'Okundu işaretle';
    okundu.addEventListener('click', function () {
      if (okunan[h.id]) { delete okunan[h.id]; } else { okunan[h.id] = 1; }
      D.yaz('okunan', okunan);
      yenidenCiz(true);
    });
    islem.appendChild(okundu);
    ust.appendChild(islem);

    icerik.appendChild(ust);

    var h3 = document.createElement('h3');
    var a = document.createElement('a');
    a.href = '#'; a.textContent = h.baslik;
    a.addEventListener('click', function (e) { e.preventDefault(); okuyucuAc(h); });
    h3.appendChild(a);
    icerik.appendChild(h3);

    if (h.ozet || h.metin) {
      var ozet = document.createElement('p');
      ozet.className = 'kart-ozet';
      ozet.textContent = (h.ozet || h.metin).slice(0, 180);
      icerik.appendChild(ozet);
    }

    var etiketler = document.createElement('div');
    etiketler.className = 'etiketler';
    h.gruplar.forEach(function (gid) {
      var g = grupHarita[gid];
      if (!g) { return; }
      var e = document.createElement('button');
      e.className = 'etiket grup';
      e.style.setProperty('--konu', g.renk);
      e.textContent = g.ad;
      e.addEventListener('click', function () { durum.grup = gid; durum.firma = ''; yenidenCiz(); });
      etiketler.appendChild(e);
    });
    h.firmalar.forEach(function (f) {
      var e = document.createElement('button');
      e.className = 'etiket'; e.textContent = kisaAd(f); e.title = f;
      e.addEventListener('click', function () { durum.firma = f; yenidenCiz(); });
      etiketler.appendChild(e);
    });
    icerik.appendChild(etiketler);
    govde.appendChild(icerik);
    kart.appendChild(govde);
    return kart;
  }

  function listeCiz(liste) {
    sonListe = liste;   // okuyucudaki ileri/geri gezinme bu listeyi kullanir
    el.liste.innerHTML = '';
    el.dahaFazlaSarma.innerHTML = '';

    if (!veri.haberler.length) {
      el.liste.innerHTML =
        '<div class="bos-durum"><h2>Henüz haber toplanmadı</h2>' +
        '<p>İlk taramayı çalıştırın; birkaç dakika sürer, sonra bu ekran dolar.</p>' +
        '<code>SimdiTara.bat</code></div>';
      return;
    }
    if (!liste.length) {
      el.liste.innerHTML =
        '<div class="bos-durum"><h2>Bu filtreyle haber yok</h2>' +
        '<p>Tarih aralığını genişletmeyi veya arama kutusunu temizlemeyi deneyin.</p></div>';
      return;
    }

    var gosterilecek = liste.slice(0, durum.limit);
    var sonGun = '';
    gosterilecek.forEach(function (h, i) {
      var g = gunAnahtari(tarihNesnesi(h.tarih));
      if (g !== sonGun) {
        sonGun = g;
        var b = document.createElement('div');
        b.className = 'gun-baslik';
        b.textContent = gunEtiketi(g);
        el.liste.appendChild(b);
      }
      var kart = kartOlustur(h);
      // Ilk gorselli haber tam genislikte - akisa ritim katiyor
      if (i === 0 && h.gorsel) { kart.classList.add('one-cikan'); }
      // Kartlar sirayla belirsin; sadece ilk ekranda, kaydirirken gecikme olmasin
      if (i < 8) { kart.style.animationDelay = (i * 45) + 'ms'; }
      else { kart.style.animation = 'none'; }
      el.liste.appendChild(kart);
    });

    if (liste.length > durum.limit) {
      var btn = document.createElement('button');
      btn.className = 'dugme sade';
      btn.textContent = 'Daha fazla göster (' + (liste.length - durum.limit) + ' haber daha)';
      btn.addEventListener('click', function () { durum.limit += SAYFA_ADIM; yenidenCiz(true); });
      el.dahaFazlaSarma.appendChild(btn);
    }
  }

  // -------------------------------------------------------------- ust ozet
  function ozetCiz(liste) {
    var m = veri.meta || {};
    var parcalar = [];
    if (m.sonTarama) {
      var t = tarihNesnesi(m.sonTarama);
      parcalar.push('Son tarama: ' + t.getDate() + ' ' + AYLAR[t.getMonth()] + ' ' + saatEtiketi(t));
    } else {
      parcalar.push('Henüz tarama yapılmadı');
    }
    parcalar.push((m.toplamHaber || 0) + ' haber' +
      (m.icerikliHaber ? ' (' + m.icerikliHaber + ' okunabilir)' : ''));
    parcalar.push((m.takipEdilenFirma || 0) + ' firma / ' + veri.gruplar.length + ' grup');
    if (m.baslangicTarihi) {
      var b = m.baslangicTarihi.split('-');
      parcalar.push(+b[2] + ' ' + AYLAR[+b[1] - 1] + ' ' + b[0] + '\'den itibaren');
    }
    el.ustOzet.textContent = parcalar.join('  ·  ');

    var f = [];
    if (durum.grup !== 'tumu' && grupHarita[durum.grup]) { f.push(grupHarita[durum.grup].ad); }
    if (durum.firma) { f.push(kisaAd(durum.firma)); }
    if (durum.tekGun) { f.push(gunEtiketi(durum.tekGun)); }
    if (durum.arama) { f.push('"' + durum.arama + '"'); }
    if (durum.gorunum === 'kayitli') { f.push('kaydedilenler'); }
    if (durum.gorunum === 'okunmamis') { f.push('okunmamışlar'); }

    el.filtreOzet.innerHTML = '<b>' + liste.length + '</b> haber gösteriliyor' +
      (f.length ? ' — ' + kacis(f.join(' · ')) : '') +
      (m.hataliSorgu ? ' <span style="color:var(--sari)">· son taramada ' + m.hataliSorgu + ' sorgu yanıt alamadı</span>' : '');
  }

  // ---------------------------------------------------------------- yeniden
  function yenidenCiz(limitiKoru) {
    if (!limitiKoru) { durum.limit = SAYFA_ADIM; }
    var liste = suzulmus();
    menuleriCiz();
    zamanSerisiCiz();
    ozetCiz(liste);
    listeCiz(liste);
  }

  function veriyiBagla() {
    veri = window.HABER_VERISI || { meta: {}, gruplar: [], haberler: [] };
    grupHarita = {};
    veri.gruplar.forEach(function (g) { grupHarita[g.id] = g; });
    veri.haberler.forEach(function (h) {
      h.gruplar = h.gruplar || [];
      h.firmalar = h.firmalar || [];
    });
  }

  // Veri dosyasini onbellege takilmadan yeniden yukler; boylece uygulama acik
  // dururken arka planda calisan tarama sonuclari ekrana dusebilir.
  function veriyiTazele(sessiz) {
    // Sifreli yayinda tazeleme sifreliTazele ile yapiliyor
    if (window.HABER_SIFRELI) { return; }
    // Okuma sirasinda listeyi altindan cekmeyelim
    if (sessiz && okuyucu && okuyucu.classList.contains('acik')) { return; }
    var s = document.createElement('script');
    s.src = 'data/haberler.js?t=' + Date.now();
    s.onload = function () {
      veriyiBagla();
      yenidenCiz();
      s.parentNode.removeChild(s);
      if (!sessiz) { el.btnYenile.classList.remove('doner'); }
    };
    s.onerror = function () {
      if (!sessiz) { el.btnYenile.classList.remove('doner'); }
      s.parentNode.removeChild(s);
    };
    if (!sessiz) { el.btnYenile.classList.add('doner'); }
    document.body.appendChild(s);
  }

  // ------------------------------------------------------------- disa aktar
  function csvIndir(liste) {
    var satirlar = [['Tarih', 'Grup', 'Firmalar', 'Başlık', 'Kaynak', 'Bağlantı']];
    liste.forEach(function (h) {
      var gruplar = h.gruplar.map(function (g) { return grupHarita[g] ? grupHarita[g].ad : g; }).join(' | ');
      satirlar.push([h.tarih.replace('T', ' '), gruplar, h.firmalar.join(' | '), h.baslik, h.kaynak, h.link]);
    });
    var csv = satirlar.map(function (s) {
      return s.map(function (h) { return '"' + String(h).replace(/"/g, '""') + '"'; }).join(';');
    }).join('\r\n');

    // BOM: Excel'in Turkce karakterleri dogru okumasi icin gerekli
    var blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'haberler-' + gunAnahtari(new Date()) + '.csv';
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  }

  // ------------------------------------------------------------------ olaylar
  var aramaZaman;
  el.arama.addEventListener('input', function () {
    clearTimeout(aramaZaman);
    aramaZaman = setTimeout(function () { durum.arama = el.arama.value; yenidenCiz(); }, 180);
  });
  el.firmaArama.addEventListener('input', function () { menuleriCiz(); });
  el.sadeceOkunmamis.addEventListener('change', function () {
    durum.sadeceOkunmamis = el.sadeceOkunmamis.checked; yenidenCiz();
  });
  el.sinifsizGoster.addEventListener('change', function () {
    durum.siniflandirilmamisGoster = el.sinifsizGoster.checked;
    if (durum.gorunum === 'siniflandirilmamis') { durum.gorunum = 'tumu'; }
    yenidenCiz();
  });
  el.btnYenile.addEventListener('click', function () { veriyiTazele(false); });
  el.btnTema.addEventListener('click', function () {
    document.body.classList.toggle('koyu');
    D.yaz('tema', document.body.classList.contains('koyu') ? 'koyu' : 'acik');
  });

  // arama satiri: buyutecle acilir, vazgecince temizlenir
  el.btnAra.addEventListener('click', function () {
    var acik = el.aramaSatiri.classList.toggle('acik');
    if (acik) { el.arama.focus(); }
  });
  el.btnAramaKapat.addEventListener('click', function () {
    el.aramaSatiri.classList.remove('acik');
    if (el.arama.value) { el.arama.value = ''; durum.arama = ''; yenidenCiz(); }
  });

  // alt sekme cubugu
  if (el.altNav) {
    el.altNav.addEventListener('click', function (e) {
      var b = e.target.closest('button');
      if (!b) { return; }
      if (b.getAttribute('data-rol') === 'filtre') {
        panelAc(!yanPanel.classList.contains('acik'));
        return;
      }
      var g = b.getAttribute('data-gorunum');
      if (g) { durum.gorunum = g; panelAc(false); yenidenCiz(); pencereBasa(); }
    });
  }
  el.panelPerde.addEventListener('click', function () { panelAc(false); });
  el.btnPanelKapat.addEventListener('click', function () { panelAc(false); });

  // basa don dugmesi
  function pencereBasa() { window.scrollTo({ top: 0, behavior: 'smooth' }); }
  el.btnYukari.addEventListener('click', pencereBasa);
  window.addEventListener('scroll', function () {
    el.btnYukari.classList.toggle('gorunur', window.scrollY > 700);
  }, { passive: true });
  el.btnHepsiOkundu.addEventListener('click', function () {
    var liste = suzulmus();
    if (!liste.length) { return; }
    if (!confirm(liste.length + ' haber okundu işaretlenecek. Devam edilsin mi?')) { return; }
    liste.forEach(function (h) { okunan[h.id] = 1; });
    D.yaz('okunan', okunan);
    yenidenCiz();
  });
  el.btnDisaAktar.addEventListener('click', function () { csvIndir(suzulmus()); });

  document.addEventListener('keydown', function (e) {
    var okuyucuAcik = okuyucu && okuyucu.classList.contains('acik');
    if (okuyucuAcik) {
      if (e.key === 'Escape')     { okuyucuKapat(); }
      if (e.key === 'ArrowLeft')  { okuyucuKaydir(-1); }
      if (e.key === 'ArrowRight') { okuyucuKaydir(1); }
      return;
    }
    if (e.key === '/' && document.activeElement !== el.arama) { e.preventDefault(); el.arama.focus(); }
    if (e.key === 'Escape' && document.activeElement === el.arama) { el.arama.blur(); }
  });

  // Uygulama acik kalirsa her 5 dakikada bir veri dosyasini yeniden okur.
  setInterval(function () { veriyiTazele(true); }, 5 * 60 * 1000);
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) { veriyiTazele(true); }
  });

  // ------------------------------------------------------------ sifreli mod
  // Yayinlanan site herkese acik bir adreste duruyor; veri dosyasi sifreli.
  // Cozme burada, tarayicida yapiliyor - parola sunucuya hic gitmiyor.
  // Yerel kullanimda (data/haberler.js duz duruyor) bu bolum hic calismaz.

  function b64Bayt(s) {
    var ham = atob(s);
    var d = new Uint8Array(ham.length);
    for (var i = 0; i < ham.length; i++) { d[i] = ham.charCodeAt(i); }
    return d;
  }

  function bayt64(d) {
    var s = '', a = new Uint8Array(d);
    for (var i = 0; i < a.length; i++) { s += String.fromCharCode(a[i]); }
    return btoa(s);
  }

  // Anahtar uretimi 600 bin turluk bir hesap; telefonda 1-2 saniye surer.
  // Tuz degismedigi surece sonucu saklayip her seferinde hesaplamiyoruz.
  //
  // ONEMLI: anahtar ancak COZME BASARILI OLDUKTAN SONRA saklaniyor. Onceden
  // once saklayip sonra deniyordu; bir kez yanlis parola girilince bozuk
  // anahtar onbellekte kaliyor ve sonraki acilislarda dogru parola bile
  // reddediliyordu. Onbellekteki anahtar tutmazsa paroladan yeniden uretilir.
  function anahtarCoz(parola, paket) {
    var tuz = b64Bayt(paket.salt), iv = b64Bayt(paket.iv), govde = b64Bayt(paket.ct);
    var tuzB64 = bayt64(tuz);
    var saklanan = D.oku('anahtar', null);

    function dene(hamAnahtar) {
      return crypto.subtle.importKey('raw', hamAnahtar, { name: 'AES-GCM' }, false, ['decrypt'])
        .then(function (k) { return crypto.subtle.decrypt({ name: 'AES-GCM', iv: iv }, k, govde); })
        .then(function (duz) { return { duz: duz, ham: hamAnahtar }; });
    }

    function turet() {
      return crypto.subtle.importKey('raw', new TextEncoder().encode(parola), 'PBKDF2', false, ['deriveBits'])
        .then(function (temel) {
          return crypto.subtle.deriveBits(
            { name: 'PBKDF2', salt: tuz, iterations: paket.it, hash: 'SHA-256' }, temel, 256);
        })
        .then(dene);
    }

    var zincir;
    if (saklanan && saklanan.tuz === tuzB64) {
      zincir = dene(b64Bayt(saklanan.k)).catch(function () {
        localStorage.removeItem('ht.anahtar');
        return turet();
      });
    } else {
      zincir = turet();
    }

    return zincir.then(function (s) {
      D.yaz('anahtar', { tuz: tuzB64, k: bayt64(s.ham) });
      return s.duz;
    });
  }

  function paketiCoz(paket, parola) {
    return anahtarCoz(parola, paket)
      .then(function (kucuk) {
        // Veri sifrelenmeden once gzip ile sikistirilmisti
        var akis = new Blob([kucuk]).stream().pipeThrough(new DecompressionStream('gzip'));
        return new Response(akis).text();
      })
      .then(function (metin) { return JSON.parse(metin); });
  }

  function sifreliVeriyiAl(parola) {
    return fetch('data/haberler.enc?t=' + Date.now(), { cache: 'no-store' })
      .then(function (y) {
        if (!y.ok) { throw new Error('Veri dosyasi indirilemedi (' + y.status + ')'); }
        return y.json();
      })
      .then(function (paket) { return paketiCoz(paket, parola); });
  }

  var sonSurum = '';

  function kilitEkrani(mesaj) {
    var perde = document.createElement('div');
    perde.className = 'kilit-perde';
    perde.innerHTML =
      '<form class="kilit" autocomplete="off">' +
        '<div class="kilit-logo">AK</div>' +
        '<h1>Avrupa Kurumsal Bülten</h1>' +
        '<p>Devam etmek için parolayı girin.</p>' +
        '<input type="password" id="kilitParola" placeholder="parola" autocomplete="current-password" ' +
          'autocapitalize="off" autocorrect="off" spellcheck="false">' +
        '<button type="submit" class="dugme">Aç</button>' +
        '<div class="kilit-hata"></div>' +
      '</form>';
    document.body.appendChild(perde);

    var hata = perde.querySelector('.kilit-hata');
    var giris = perde.querySelector('#kilitParola');
    if (mesaj) { hata.textContent = mesaj; }
    // Kapak kilit ekranina gecsin
    kapagiKaldir();
    setTimeout(function () { giris.focus(); }, 660);

    perde.querySelector('form').addEventListener('submit', function (e) {
      e.preventDefault();
      var parola = giris.value.trim();
      if (!parola) { return; }
      hata.textContent = '';
      hata.className = 'kilit-hata';
      var dugme = perde.querySelector('button');
      dugme.disabled = true;
      dugme.textContent = 'Açılıyor…';

      sifreliVeriyiAl(parola).then(function (v) {
        D.yaz('parola', parola);
        window.HABER_VERISI = v;
        perde.remove();
        baslat();
      }).catch(function (e) {
        // Yanlis parola AES dogrulamasinda takilir; agdan gelen hatayi ayirt et
        localStorage.removeItem('ht.anahtar');
        dugme.disabled = false;
        dugme.textContent = 'Aç';
        hata.textContent = /indirilemedi|Failed to fetch|NetworkError/i.test(e.message || '')
          ? 'Veri indirilemedi. Bağlantını kontrol et.'
          : 'Parola yanlış.';
        giris.select();
      });
    });
  }

  // Kapak en az bu kadar durur; veri erken hazir olsa bile goz yetissin diye.
  var KAPAK_SURESI = 1500;
  var acilisAni = Date.now();

  function kapagiKaldir() {
    var kapak = document.getElementById('kapak');
    if (!kapak) { return; }
    var kalan = Math.max(0, KAPAK_SURESI - (Date.now() - acilisAni));
    setTimeout(function () {
      kapak.classList.add('gizli');
      setTimeout(function () { if (kapak.parentNode) { kapak.parentNode.removeChild(kapak); } }, 600);
    }, kalan);
  }

  function baslat() {
    veriyiBagla();
    yenidenCiz();
    if (veri.meta) { sonSurum = veri.meta.sonTarama || ''; }
    kapagiKaldir();
  }

  // Sifreli modda buyuk dosyayi her seferinde indirmeyelim: once kucucuk bir
  // surum dosyasina bakip degisip degismedigine karar veriyoruz.
  function sifreliTazele() {
    if (okuyucu && okuyucu.classList.contains('acik')) { return; }
    fetch('data/surum.json?t=' + Date.now(), { cache: 'no-store' })
      .then(function (y) { return y.json(); })
      .then(function (s) {
        if (!s.sonTarama || s.sonTarama === sonSurum) { return null; }
        return sifreliVeriyiAl(D.oku('parola', ''));
      })
      .then(function (v) {
        if (!v) { return; }
        window.HABER_VERISI = v;
        baslat();
      })
      .catch(function () { /* bir sonraki denemede tekrar bakilir */ });
  }

  // ------------------------------------------------------------------ baslat
  if (window.HABER_SIFRELI) {
    el.btnYenile.addEventListener('click', function () { sonSurum = ''; sifreliTazele(); });
    setInterval(sifreliTazele, 5 * 60 * 1000);
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) { sifreliTazele(); }
    });

    var pk = D.oku('parola', '');
    if (pk) {
      sifreliVeriyiAl(pk).then(function (v) {
        window.HABER_VERISI = v;
        baslat();
      }).catch(function () {
        localStorage.removeItem('ht.anahtar');
        kilitEkrani('');
      });
    } else {
      kilitEkrani('');
    }
  } else {
    baslat();
  }
})();
