namespace TerakarsaApp.Shared.Tni;

// Prompt 62: import personel PDH TNI AD dari export Google Form (.xlsx).
// Alur dua langkah: Unggah (staging + cek) lalu Simpan (commit ke tni.personel).

// Satu baris Excel setelah dipetakan API. Nama properti ini dipakai APA ADANYA
// sebagai nama field JSON yang dibaca OPENJSON di tni.SIS_Import_Stage --
// jangan diubah tanpa mengubah SP-nya juga.
public class TniImportRow
{
    public int BarisKe { get; set; }                 // nomor baris di file Excel
    public DateTime? SubmittedAt { get; set; }
    public string? EmailPengisi { get; set; }        // email PENGISI form
    public string? Gender { get; set; }              // sudah dinormalisasi API
    public string? Pangkat { get; set; }
    public string? Nama { get; set; }
    public string? Nrp { get; set; }
    public string? NoHp { get; set; }
    public int? TinggiBadan { get; set; }
    public int? BeratBadan { get; set; }
    public string? SizeBajuIsian { get; set; }       // arsip, tidak divalidasi
    public string? SizeCelanaIsian { get; set; }
    public string? Kategori { get; set; }            // UKUR | TU_SIZING
    public string? AreaName { get; set; }
    public string? SatuanName { get; set; }
    public string? KodeKemeja { get; set; }
    public string? KodeCelana { get; set; }

    // 8 ukuran badan kemeja
    public decimal? LingkarLeher { get; set; }
    public decimal? LebarBahu { get; set; }
    public decimal? LingkarDada { get; set; }
    public decimal? LingkarPerut { get; set; }
    public decimal? PanjangBadanDepan { get; set; }
    public decimal? PanjangLengan { get; set; }
    public decimal? LingkarLengan { get; set; }
    public decimal? LingkarKetiak { get; set; }

    // 7 ukuran badan celana
    public decimal? LingkarPinggangCelana { get; set; }
    public decimal? LingkarPinggul { get; set; }
    public decimal? LingkarPesak { get; set; }
    public decimal? LingkarPaha { get; set; }
    public decimal? LingkarLutut { get; set; }
    public decimal? LingkarCelanaBawah { get; set; }
    public decimal? PanjangCelana { get; set; }
}

public class TniImportBatchDto
{
    public int BatchId { get; set; }
    public int OrderId { get; set; }
    public string NamaFile { get; set; } = string.Empty;
    public int JumlahBaris { get; set; }
    public int JumlahBaru { get; set; }
    public int JumlahDiperbarui { get; set; }
    public int JumlahReview { get; set; }
    public int JumlahDitolak { get; set; }
    public DateTime? CommittedAt { get; set; }
    public string? CommittedByNama { get; set; }
    public string? Catatan { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? CreatedByNama { get; set; }

    // Baris yang akan disimpan kalau tombol Simpan ditekan: Baru + Diperbarui.
    // (Review ikut tersimpan -- hitungannya sudah termasuk di dua angka itu.)
    public int JumlahAkanDisimpan => JumlahBaru + JumlahDiperbarui;
    public bool SudahDisimpan => CommittedAt.HasValue;
}

public class TniImportBarisDto
{
    public int BarisKe { get; set; }
    public string? Nrp { get; set; }
    public string? Nama { get; set; }
    public string Hasil { get; set; } = string.Empty;   // TOLAK | REVIEW
    public string? Aksi { get; set; }                   // BARU | PERBARUI
    public string? Pesan { get; set; }
}

public class TniImportHasilDto
{
    public TniImportBatchDto? Batch { get; set; }
    public List<TniImportBarisDto> Baris { get; set; } = new();
}

public class TniImportCommitHasilDto
{
    public int JumlahBaru { get; set; }
    public int JumlahDiperbarui { get; set; }
}
