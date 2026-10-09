namespace TerakarsaApp.Shared.Tni;

// Prompt 68: pengajuan & persetujuan pembatalan scan PDH TNI AD.
//
// Scan tidak bisa dihapus langsung. Staff (TNI_PDH) mengajukan dengan alasan,
// user TNI_PDH_APPROVE memutus di /tni/pembatalan.
//
//   BOX -> personel keluar dari box; box yang sudah ditutup terbuka lagi.
//   SET -> personel kembali "Kartu tercetak"; kemeja & celana kembali ke stok
//          lewat mutasi BONGKAR +1 (baris TERPAKAI tidak pernah dihapus).

public class TniPembatalanDto
{
    public int PembatalanId { get; set; }
    public int PersonelId { get; set; }
    public string Jenis { get; set; } = string.Empty;    // SET | BOX
    public string Status { get; set; } = string.Empty;   // MENUNGGU | DISETUJUI | DITOLAK

    public string KodeRef { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string Nama { get; set; } = string.Empty;
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;
    public string AreaCode { get; set; } = string.Empty;
    public string StatusProgres { get; set; } = string.Empty;

    public string PolaKemejaKode { get; set; } = string.Empty;
    public string PolaCelanaKode { get; set; } = string.Empty;

    public string? BoxCodeAsal { get; set; }
    public string? BoxCodeSekarang { get; set; }
    public bool BoxAsalTertutup { get; set; }            // -> peringatan "box akan terbuka lagi"

    public string Alasan { get; set; } = string.Empty;
    public DateTime DiajukanAt { get; set; }
    public string? DiajukanOlehNama { get; set; }
    public DateTime? DiputusAt { get; set; }
    public string? DiputusOlehNama { get; set; }
    public string? CatatanKeputusan { get; set; }

    public int TotalCount { get; set; }

    public bool Menunggu => Status == "MENUNGGU";
    public bool Disetujui => Status == "DISETUJUI";
    public bool Ditolak => Status == "DITOLAK";
    public bool JenisBox => Jenis == "BOX";

    public string JenisLabel => JenisBox ? "Batal masuk box" : "Batal set jadi";

    // Keterangan efek yang ditampilkan di kartu pengajuan.
    public string EfekLabel => JenisBox
        ? $"di {BoxCodeAsal ?? BoxCodeSekarang ?? "-"}"
        : $"kemeja {PolaKemejaKode} + celana {PolaCelanaKode} kembali ke stok";
}

public class TniPembatalanAjukanRequest
{
    public int PersonelId { get; set; }
    public string Jenis { get; set; } = string.Empty;    // SET | BOX
    public string Alasan { get; set; } = string.Empty;
}

public class TniPembatalanPutusanRequest
{
    public string? Catatan { get; set; }                 // wajib untuk TOLAK
}

public class TniPembatalanHasilDto
{
    public int PembatalanId { get; set; }
    public string? KodeRef { get; set; }
    public string? Jenis { get; set; }
    public string? BoxCode { get; set; }
    public bool BoxDibukaUlang { get; set; }
}

// Pembungkus hasil aksi supaya pesan RAISERROR SP bisa ditampilkan apa adanya.
public class TniPembatalanAksiHasil
{
    public bool Ok { get; set; }
    public string Pesan { get; set; } = string.Empty;
    public TniPembatalanHasilDto? Data { get; set; }
}
