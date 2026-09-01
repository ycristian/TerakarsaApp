using System.Net.Http.Json;
using TerakarsaApp.Shared.Bundles;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.Employees;
using TerakarsaApp.Shared.Packs;
using TerakarsaApp.Shared.Projects;
using TerakarsaApp.Shared.Resources;
using TerakarsaApp.Shared.Stations;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.Client.Services;

// Dipakai khusus oleh halaman /station (perangkat, tanpa login). HttpClient-nya
// disuntikkan lewat typed client "StationDeviceAPI" yang memakai StationTokenHandler,
// BUKAN HttpClient JWT biasa yang dipakai *ApiService lain.
public class StationDeviceApiService
{
    private readonly HttpClient _http;

    public StationDeviceApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<StationMeDto?> GetMeAsync()
    {
        var response = await _http.GetAsync("api/station/me");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<StationMeDto>();
    }

    // Prompt 20: tukar kode pairing dengan station_token baru. Endpoint anonim di sisi
    // server -- StationTokenHandler cukup tidak mengirim header saat belum ada token tersimpan.
    public async Task<(bool Success, string Error, StationTokenResult? Result)> ClaimAsync(string code)
    {
        var response = await _http.PostAsJsonAsync("api/station-device/claim", new StationClaimRequest { Code = code });
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<StationTokenResult>();
            return (true, string.Empty, result);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Kode pairing tidak valid atau sudah kedaluwarsa." : error.Trim('"'), null);
    }

    // Prompt 20: logout perangkat -- hanguskan token di server (UNPAIR), localStorage
    // dibersihkan di sisi Razor setelah panggilan ini.
    public async Task<bool> LogoutAsync()
    {
        var response = await _http.PostAsync("api/station-device/logout", null);
        return response.IsSuccessStatusCode;
    }

    public async Task<List<ResourceLookupDto>> GetResourcesAsync()
    {
        var response = await _http.GetAsync("api/station/resources");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    // Prompt 24: dropdown "Penjahit" di modal Buat Bundle/Edit Bundle -- divisi lain dari
    // divisi stasiun ini sendiri (lihat FirstBundleStepDivisionId).
    public async Task<List<ResourceLookupDto>> GetResourcesByDivisionAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/station/resources/{divisionId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    // Prompt 32: dropdown "Penjahit" (employee) cascading di bawah dropdown Line, menggantikan
    // input teks bebas di modal Buat Bundle/Edit Bundle.
    public async Task<List<EmployeeLookupDto>> GetEmployeesByResourceAsync(int resourceId)
    {
        var response = await _http.GetAsync($"api/station/employees/{resourceId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<EmployeeLookupDto>>() ?? new();
    }

    // Prompt 24: ringkasan per size untuk modal "Buat Bundle".
    public async Task<List<BundleSizeSummaryDto>> GetBundlingSummaryAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/station/bundling/articles/{articleId}/summary");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<BundleSizeSummaryDto>>() ?? new();
    }

    // Prompt 24: "Buat Bundle" dari kartu WIP station Bundling.
    public async Task<(bool Success, string Error, BundleCreateResult? Result)> CreateBundleAsync(StationBundleCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/bundles", request);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<BundleCreateResult>();
            return (true, string.Empty, result);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuat bundle." : error.Trim('"'), null);
    }

    // Prompt 24: Edit bundle dari tab OUT station Bundling.
    public async Task<(bool Success, string Error)> UpdateBundleAsync(int bundleId, StationBundleUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/station/bundles/{bundleId}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan perubahan." : error.Trim('"'));
    }

    // Fix: "Hapus" bundle dari tab OUT station Bundling (baris sudah received_at tapi masih
    // WIP murni & dalam jendela 1 jam -- lihat StationPendingHandoverDto.ReceivedAt).
    public async Task<(bool Success, string Error)> DeleteBundleAsync(int bundleId, string reason)
    {
        var response = await _http.DeleteAsync($"api/station/bundles/{bundleId}?reason={Uri.EscapeDataString(reason)}");
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus bundle." : error.Trim('"'));
    }

    // Prompt 24: Cetak Ulang label -- dipakai semua kartu bundle di station + BundleScanCard.
    // Fix: copies (default 1) -- jumlah label yang dicetak, diisi user lewat modal konfirmasi.
    public async Task<(bool Success, string Error)> ReprintBundleAsync(int bundleId, int copies = 1)
    {
        var response = await _http.PostAsync($"api/station/bundles/{bundleId}/reprint?copies={copies}", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak ulang label." : error.Trim('"'));
    }

    // Prompt: "Print Label Cacat" -- reprint label bundle N lembar, remark di-override dengan
    // catatan + ringkasan qty cacat.
    public async Task<(bool Success, string Error)> PrintDefectLabelAsync(int bundleId, int copies, string? remark)
    {
        var response = await _http.PostAsJsonAsync($"api/station/bundles/{bundleId}/print-defect-label", new BundlePrintDefectLabelRequest { Copies = copies, Remark = remark });
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak label cacat." : error.Trim('"'));
    }

    // Fix: "Cetak Reject" -- nota reject untuk satu baris log timeline (BundleScanCard),
    // tombol client hanya tampil kalau baris itu punya reject > 0.
    public async Task<(bool Success, string Error)> PrintRejectAsync(int workflowLogId, int copies = 1)
    {
        var response = await _http.PostAsync($"api/station/logs/{workflowLogId}/print-reject?copies={copies}", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak nota reject." : error.Trim('"'));
    }

    // Prompt 41 (lanjutan): "Print Hasil" -- cetak kupon manual segera setelah Kirim Hasil,
    // muncul di BundleScanCard selama baris masih EDIT (belum diterima) dan step-nya
    // ber-print_kupon = 1.
    public async Task<(bool Success, string Error)> PrintHasilAsync(int workflowLogId)
    {
        var response = await _http.PostAsync($"api/station/logs/{workflowLogId}/print-hasil", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak kupon." : error.Trim('"'));
    }

    // Prompt 22b: resourceId = operator sesi saat ini, dipakai server untuk filter antrian
    // ke Line operator ini (lihat EffectiveResourceId di StationDeviceController).
    public async Task<List<StationPendingReceiveDto>> GetPendingReceivesAsync(int? resourceId)
    {
        var response = await _http.GetAsync($"api/station/pending-receives{ResourceIdQuery(resourceId)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationPendingReceiveDto>>() ?? new();
    }

    public async Task<List<StationPendingHandoverDto>> GetPendingHandoverAsync(int? resourceId)
    {
        var response = await _http.GetAsync($"api/station/pending-handover{ResourceIdQuery(resourceId)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationPendingHandoverDto>>() ?? new();
    }

    public async Task<List<StationRecentReceivedDto>> GetRecentReceivedAsync(int? resourceId)
    {
        var response = await _http.GetAsync($"api/station/recent-received{ResourceIdQuery(resourceId)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationRecentReceivedDto>>() ?? new();
    }

    // Prompt 12e: tab "Dikerjakan".
    public async Task<List<StationInProgressDto>> GetInProgressAsync(int? resourceId)
    {
        var response = await _http.GetAsync($"api/station/in-progress{ResourceIdQuery(resourceId)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationInProgressDto>>() ?? new();
    }

    // Prompt 23: kartu permanen (artikel x step non-bundle) di tab WIP -- tanpa resourceId
    // (kartu ini tidak terikat Line).
    public async Task<List<StationActiveWorkDto>> GetActiveWorkAsync()
    {
        var response = await _http.GetAsync("api/station/active-work");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationActiveWorkDto>>() ?? new();
    }

    // Fix: foto utama artikel untuk kartu "Buat Bundle" di tab WIP.
    public async Task<(byte[] Bytes, string ContentType)?> GetArticlePhotoAsync(int articleId)
    {
        try
        {
            var response = await _http.GetAsync($"api/station/articles/{articleId}/photo");
            if (!response.IsSuccessStatusCode) return null;

            var bytes = await response.Content.ReadAsByteArrayAsync();
            var contentType = response.Content.Headers.ContentType?.MediaType ?? "application/octet-stream";
            return (bytes, contentType);
        }
        catch (HttpRequestException)
        {
            return null;
        }
    }

    // Prompt 23: grid "Kirim Hasil" non-bundle -- pindahan dari WorkflowInputApiService.
    public async Task<(bool Success, string Error, int? ArticleSizeId)> CreateNonBundleLogBatchAsync(StationNonBundleBatchCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/nonbundle-logs/batch", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty, null);

        var result = await response.Content.ReadFromJsonAsync<StationNonBundleBatchResult>();
        return (false, string.IsNullOrWhiteSpace(result?.Error) ? "Gagal menyimpan data." : result.Error, result?.ArticleSizeId);
    }

    // Prompt 12e: strip 3 angka besar (Masuk/Dikerjakan/Dikirim).
    public async Task<StationCountsDto> GetCountsAsync(int? resourceId)
    {
        var response = await _http.GetAsync($"api/station/counts{ResourceIdQuery(resourceId)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<StationCountsDto>() ?? new();
    }

    // Prompt 12e: tab "Dikirim" (dulu "Menunggu Diserahkan") -- ulang pakai endpoint
    // pending-handover yang sudah cocok dengan definisi Dikirim, hanya rename di sisi client.
    public async Task<List<StationPendingHandoverDto>> GetOutboundAsync(int? resourceId) => await GetPendingHandoverAsync(resourceId);

    private static string ResourceIdQuery(int? resourceId) =>
        resourceId.HasValue ? $"?resourceId={resourceId.Value}" : string.Empty;

    // Prompt 14: info kuota qty step ber-bundle ("Masuk / Tercatat / Sisa") sebelum submit.
    public async Task<WorkflowQuotaInfoDto?> GetQuotaInfoAsync(int articleWorkflowId, int bundleId)
    {
        var response = await _http.GetAsync($"api/station/quota-info?articleWorkflowId={articleWorkflowId}&bundleId={bundleId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<WorkflowQuotaInfoDto>();
    }

    // Prompt 40: dropdown "Diterima Oleh ({divisi tujuan})" wajib di form Kirim Hasil.
    public async Task<List<ResourceLookupDto>> GetReceiverOptionsAsync(int articleWorkflowId, int? bundleId)
    {
        var url = $"api/station/receiver-options?articleWorkflowId={articleWorkflowId}";
        if (bundleId.HasValue) url += $"&bundleId={bundleId.Value}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<BundleScanInfoDto?> ScanAsync(string serial, int? resourceId)
    {
        var url = $"api/station/scan/{Uri.EscapeDataString(serial)}";
        if (resourceId.HasValue) url += $"?resourceId={resourceId.Value}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<BundleScanInfoDto>();
    }

    // Prompt 28: panel Penyesuaian di /b/{serial} (BundleScanCard).
    public async Task<(bool Success, string Error)> AdjustAsync(StationAdjustRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/adjust", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan penyesuaian." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> ReceiveAsync(StationReceiveRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/receive", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menerima." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> CompleteAsync(StationCompleteRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/complete", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyelesaikan." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateLogAsync(int workflowLogId, StationLogUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/station/logs/{workflowLogId}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan perubahan." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UnreceiveAsync(int workflowLogId, StationUnreceiveRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/station/logs/{workflowLogId}/unreceive", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membatalkan penerimaan." : error.Trim('"'));
    }

    // Prompt 12e: "Batal Serah" di tab Dikirim.
    public async Task<(bool Success, string Error)> CancelHandoverAsync(int workflowLogId, StationCancelHandoverRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/station/logs/{workflowLogId}/cancel-handover", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membatalkan serah." : error.Trim('"'));
    }

    // Prompt 12e: "Revisi" di tab Dikirim.
    public async Task<(bool Success, string Error)> ReviseHandoverAsync(int workflowLogId, StationReviseHandoverRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/station/logs/{workflowLogId}/revise-handover", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan revisi." : error.Trim('"'));
    }

    // Prompt 25: modul Packing -- dropdown project ("aktif") dipakai untuk memilih project
    // sebelum masuk sub-tab Stok Siap Pack/Karung.
    public async Task<List<ProjectDto>> GetPackingProjectsAsync()
    {
        var response = await _http.GetAsync("api/station/packing/projects");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ProjectDto>>() ?? new();
    }

    public async Task<List<PackStockAvailableDto>> GetPackingStockAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/station/packing/stock/{projectId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<PackStockAvailableDto>>() ?? new();
    }

    public async Task<ProjectPackingDto> GetPackingPacksAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/station/packing/packs/{projectId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ProjectPackingDto>() ?? new();
    }

    public async Task<(bool Success, string Error, PackCreateResult? Result)> CreatePackAsync(PackCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/packing/packs", request);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<PackCreateResult>();
            return (true, string.Empty, result);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuat karung." : error.Trim('"'), null);
    }

    public async Task<(bool Success, string Error)> UpdatePackPlanAsync(int packId, PackUpdatePlanRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/station/packing/packs/{packId}/plan", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan planning." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> ConfirmPackAsync(int packId, PackConfirmRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/station/packing/packs/{packId}/confirm", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan konfirmasi." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> ReprintPackAsync(int packId, int copies = 1)
    {
        var response = await _http.PostAsync($"api/station/packing/packs/{packId}/reprint?copies={copies}", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak ulang label." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> DeletePackAsync(int packId, string reason)
    {
        var response = await _http.DeleteAsync($"api/station/packing/packs/{packId}?reason={Uri.EscapeDataString(reason)}");
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus karung." : error.Trim('"'));
    }

    public async Task<PackScanInfoDto?> ScanPackAsync(string serial)
    {
        var response = await _http.GetAsync($"api/station/packing/scan/{Uri.EscapeDataString(serial)}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<PackScanInfoDto>();
    }

    // Prompt 42: dropdown "Divisi" (level pertama) di tab Rekap Produksi.
    public async Task<List<DivisionDto>> GetStationDivisionsAsync()
    {
        var response = await _http.GetAsync("api/station/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }

    // Prompt 42: tab "Rekap Produksi" -- header + detail harian + WIP snapshot, menggantikan
    // Rekap Penjahit Prompt 41.
    public async Task<RekapStrukResultDto?> GetRekapStrukAsync(string level, int divisionId, int? resourceId, int? employeeId, DateTime date)
    {
        var url = $"api/station/rekap-struk?level={Uri.EscapeDataString(level)}&divisionId={divisionId}&date={date:yyyy-MM-dd}";
        if (resourceId.HasValue) url += $"&resourceId={resourceId.Value}";
        if (employeeId.HasValue) url += $"&employeeId={employeeId.Value}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<RekapStrukResultDto>();
    }

    public async Task<(bool Success, string Error)> PrintRekapStrukAsync(RekapStrukPrintRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/rekap-struk/print", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak rekap." : error.Trim('"'));
    }

    // Ad hoc (2026-08-28): tombol "Cetak WIP" -- terpisah dari Cetak Struk di atas.
    public async Task<(bool Success, string Error)> PrintRekapWipAsync(RekapWipPrintRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/rekap-wip/print", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak WIP." : error.Trim('"'));
    }
}
