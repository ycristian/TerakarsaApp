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

    // Sisa > 0 dan seluruh sisanya bisa dipenuhi dari stok bebas.
    public bool BisaTuntas => Sisa > 0 && BisaDibuat == Sisa;

    public int PersenSelesai =>
        TotalPersonel == 0 ? 0 : (int)Math.Round(SudahMasukBox * 100.0 / TotalPersonel);
}

// Kekurangan per pola, untuk ringkasan "kurang 20 kemeja LD_108_P".
public class TniKekuranganDto
{
    public string JenisItem { get; set; } = string.Empty;   // KEMEJA | CELANA
    public string Kode { get; set; } = string.Empty;
    public int Kurang { get; set; }
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
