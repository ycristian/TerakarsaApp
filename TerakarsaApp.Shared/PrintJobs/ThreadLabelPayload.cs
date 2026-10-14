using System.Text.Json.Serialization;

namespace TerakarsaApp.Shared.PrintJobs;

// Prompt 73: payload print_jobs untuk job_type THREAD_SKU_LABEL & THREAD_SPLIT_LABEL
// (label benang 30x20 mm). Dirakit inv.SIS_ThreadLabel_Enqueue lewat FOR JSON PATH
// dengan nama kolom snake_case -- dicocokkan lewat JsonPropertyName, pola sama dengan
// BundleLabelPayload.
//
// SATU bentuk payload untuk kedua job type: kolom yang tidak relevan dibiarkan null
// (cone_code & weight_gram hanya ada di label split).
public class ThreadLabelPayload
{
    [JsonPropertyName("kind")]
    public string Kind { get; set; } = "SKU";          // SKU | SPLIT

    // Isi QR: `TB:<sku_code>` untuk label SKU, `TS:<cone_code>` untuk label split.
    [JsonPropertyName("qr")]
    public string Qr { get; set; } = string.Empty;

    [JsonPropertyName("sku_code")]
    public string? SkuCode { get; set; }

    [JsonPropertyName("color_code")]
    public string? ColorCode { get; set; }

    [JsonPropertyName("color_name")]
    public string? ColorName { get; set; }

    [JsonPropertyName("brand")]
    public string? Brand { get; set; }

    [JsonPropertyName("thread_type")]
    public string? ThreadType { get; set; }

    [JsonPropertyName("cone_size")]
    public string? ConeSize { get; set; }              // KECIL | BESAR

    [JsonPropertyName("cone_code")]
    public string? ConeCode { get; set; }              // label split saja

    [JsonPropertyName("weight_gram")]
    public int? WeightGram { get; set; }               // label split saja

    [JsonPropertyName("copies")]
    public int Copies { get; set; } = 1;

    public bool IsSplit => Kind == "SPLIT";
}
