namespace TerakarsaApp.Shared.Tni;

// Prompt 65: Perintah Kerja & saran prioritas PDH TNI AD.
//
// "Bisa dibuat" dihitung dengan greedy di API (bukan SP) -- sifatnya SARAN,
// bukan validasi: supervisor bebas memilih, dan scan tidak pernah ditolak
// karena angka ini.

// Satu baris kandidat (personel BELUM_CETAK) dari tni.SIS_PerintahKerja_Data.
public class TniKandidatDto
{
    public int PersonelId { get; set; }
    public string KodeRef { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string Nama { get; set; } = string.Empty;
    public int AreaId { get; set; }
    public string AreaCode { get; set; } = string.Empty;
    public string AreaName { get; set; } = string.Empty;
    public int SatuanId { get; set; }
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;
    public int PolaKemejaId { get; set; }
    public string PolaKemejaKode { get; set; } = string.Empty;
    public int PolaCelanaId { get; set; }
    public string PolaCelanaKode { get; set; } = string.Empty;

    // Diisi API: kemeja ATAU celananya termasuk filter size prioritas perangkat.
    public bool IsSizePrioritas { get; set; }
}

public class TniStokBebasDto
{
    public int PolaId { get; set; }
    public string Kode { get; set; } = string.Empty;
    public int StokBebas { get; set; }
    public int Saldo { get; set; }
}

// Ringkasan satu rawatan untuk layar "Pilih rawatan".
public class TniRawatanDto
{
    public int AreaId { get; set; }
    public string AreaCode { get; set; } = string.Empty;
    public string AreaName { get; set; } = string.Empty;

    public int TotalPersonel { get; set; }
    public int Sisa { get; set; }              // kandidat BELUM_CETAK
    public int BisaDibuat { get; set; }        // greedy atas seluruh kandidat rawatan
    public int SatuanBisaTuntas { get; set; }
    public int SudahMasukBox { get; set; }

    // Filter size prioritas aktif: berapa dari BisaDibuat yang memakai size itu.
    public int BisaSizePrioritas { get; set; }
    // Barang (kemeja + celana) size terpilih yang terpakai vs total stok bebasnya.
    // Pakai == Stok berarti stok size terpilih habis terpakai.
    public int PakaiSizePrioritas { get; set; }
    public int StokSizePrioritas { get; set; }

    // Stok bebas yang dikunci satuan bergembok di rawatan ini (alter_81).
    public int DikunciKemeja { get; set; }
    public int DikunciCelana { get; set; }

    public int PersenSelesai =>
        TotalPersonel == 0 ? 0 : (int)Math.Round(SudahMasukBox * 100.0 / TotalPersonel);
}

// Satu satuan di daftar saran.
public class TniSatuanSaranDto
{
    public int SatuanId { get; set; }
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;

    public int TotalPersonel { get; set; }
    public int Sisa { get; set; }
    public int BisaDibuat { get; set; }
    public int SudahMasukBox { get; set; }

    // Dari tni.v_personel: dicetak = status selain BELUM_CETAK;
    // set jadi = SET_JADI/MASUK_BOX/TERKIRIM (kumulatif, jadi >= SudahMasukBox).
    public int SudahDicetak { get; set; }
    public int SudahSetJadi { get; set; }

    // Bintang prioritas (tni.satuan.prioritas_at, alter_78) -- selalu di urutan teratas.
    public bool IsPrioritas { get; set; }

    // Gembok kunci stok (tni.satuan.kunci_stok_at, alter_81): stok bebas disisihkan untuk
    // kebutuhan BELUM_CETAK satuan ini; Dikunci* = jatah yang sedang ditahan untuknya.
    public bool IsKunciStok { get; set; }
    public int DikunciKemeja { get; set; }
    public int DikunciCelana { get; set; }

    // Filter size prioritas aktif: berapa dari BisaDibuat yang memakai size itu.
    public int BisaSizePrioritas { get; set; }
    // Barang (kemeja + celana) size terpilih yang terpakai vs total stok bebasnya.
    // Pakai == Stok berarti stok size terpilih habis terpakai.
    public int PakaiSizePrioritas { get; set; }
    public int StokSizePrioritas { get; set; }

    // Sisa > 0 dan seluruh sisanya bisa dipenuhi dari stok bebas.
    public bool BisaTuntas => Sisa > 0 && BisaDibuat == Sisa;

    public int PersenSelesai =>
        TotalPersonel == 0 ? 0 : (int)Math.Round(SudahMasukBox * 100.0 / TotalPersonel);

    public int PersenSetJadi =>
        TotalPersonel == 0 ? 0 : (int)Math.Round(SudahSetJadi * 100.0 / TotalPersonel);

    public int PersenDicetak =>
        TotalPersonel == 0 ? 0 : (int)Math.Round(SudahDicetak * 100.0 / TotalPersonel);
}

public class TniSatuanPrioritasRequest
{
    public bool Prioritas { get; set; }
}

public class TniSatuanKunciStokRequest
{
    public bool Kunci { get; set; }
}

// Kekurangan per pola, untuk ringkasan "kurang 20 kemeja LD_108_P".
public class TniKekuranganDto
{
    public string JenisItem { get; set; } = string.Empty;   // KEMEJA | CELANA
    public string Kode { get; set; } = string.Empty;
    public int Kurang { get; set; }

    // P | PG | W | WH (kemeja), P | W (celana) -- sama dengan halaman Stok.
    // List sudah terurut dari API: kemeja dulu, lalu grup, lalu size.
    public string GrupGender { get; set; } = string.Empty;

    // Bintang: ada personel yang barang pasangannya SUDAH ada di stok, tinggal menunggu
    // pola ini -- begitu pola ini masuk, setnya langsung jadi. Prioritaskan produksinya.
    public bool AdaPasangan { get; set; }
}

// Satu orang di tab "Belum bisa", beserta pola yang kurang.
public class TniBelumBisaDto
{
    public TniKandidatDto Personel { get; set; } = new();
    public bool KemejaKurang { get; set; }
    public bool CelanaKurang { get; set; }

    public string Alasan =>
        (KemejaKurang, CelanaKurang) switch
        {
            (true, true) => $"Kemeja {Personel.PolaKemejaKode} & celana {Personel.PolaCelanaKode} kosong",
            (true, false) => $"Kemeja {Personel.PolaKemejaKode} kosong",
            (false, true) => $"Celana {Personel.PolaCelanaKode} kosong",
            _ => string.Empty
        };
}

public class TniSatuanDetailDto
{
    public int SatuanId { get; set; }
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;
    public string AreaName { get; set; } = string.Empty;

    public List<TniKandidatDto> BisaDibuat { get; set; } = new();
    public List<TniBelumBisaDto> BelumBisa { get; set; } = new();
    public List<TniKekuranganDto> Kekurangan { get; set; } = new();

    // Filter size prioritas: barang size terpilih yang terpakai vs total stok bebasnya.
    public int PakaiSizePrioritas { get; set; }
    public int StokSizePrioritas { get; set; }

    // polaId -> stok yang boleh dipakai satuan ini (bebas tanpa kunci + jatah kuncinya
    // sendiri), > 0 saja. Untuk kolom Stok/Sisa di konfirmasi cetak.
    public Dictionary<int, int> TersediaKemeja { get; set; } = new();
    public Dictionary<int, int> TersediaCelana { get; set; } = new();
}

// Satu kartu yang sudah tercetak tapi belum di-scan Set Jadi.
public class TniDijatahDto
{
    public int PersonelId { get; set; }
    public string KodeRef { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string Nama { get; set; } = string.Empty;
    public string PolaKemejaKode { get; set; } = string.Empty;
    public string PolaCelanaKode { get; set; } = string.Empty;
    public DateTime? PrintedAt { get; set; }
    public int PrintCount { get; set; }
    public string? PrintedByNama { get; set; }
    // Job kartu terakhir di dbo.print_jobs (urutan keluar printer + status printer).
    public int? PrintJobId { get; set; }
    public string? PrintJobStatus { get; set; }      // DONE / ERROR / PENDING / ...
    public DateTime? PrintJobPrintedAt { get; set; }
}

public class TniCetakRequest
{
    public List<int> PersonelIds { get; set; } = new();
}

public class TniCetakHasilDto
{
    public int JumlahJob { get; set; }
}

public class TniLepasHasilDto
{
    public int JumlahDilepas { get; set; }
    // kode_ref yang dilewati karena sudah Set Jadi (tidak bisa dilepas)
    public string? DilewatiKodeRef { get; set; }
}
