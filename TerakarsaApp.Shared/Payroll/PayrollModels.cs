namespace TerakarsaApp.Shared.Payroll;

// Prompt 55/56: periode gajian (payroll_periods) -- rumus Sabtu 10:00 Prompt 30 yang kini
// jadi baris bernomor. Dipakai dropdown "Periode Gajian" pada modal LOCK di stasiun.
// Lihat SIS_PayrollPeriod_Options di sql/sp_PayrollPeriod_Manage.sql.
public class PayrollPeriodOptionDto
{
    public int PayrollPeriodId { get; set; }
    // Format 'YY-wNN', mis. '26-w40' -- nomor periode internal (Sabtu 10:00), BUKAN ISO week.
    // Format lama '2026-P40' diubah lewat sql/alter_payroll_period_code_format.sql.
    public string PeriodCode { get; set; } = string.Empty;
    public DateTime PeriodStart { get; set; }   // inklusif
    public DateTime PeriodEnd { get; set; }     // eksklusif
    // Periode yang MEMUAT @DefaultAt (created_at terbaru di antara baris terpilih) --
    // itu yang diperlihatkan terpilih saat modal dibuka.
    public bool IsDefault { get; set; }
}
