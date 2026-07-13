using System.Text.Json.Serialization;

namespace TerakarsaApp.Shared.PrintJobs;

public class PrintJobClaimRequest
{
    public int BatchSize { get; set; } = 5;
}

public class PrintJobClaimedDto
{
    public int PrintJobId { get; set; }
    public string JobType { get; set; } = string.Empty;
    public int RefId { get; set; }
    public string Payload { get; set; } = string.Empty;
    public int RetryCount { get; set; }
}

public class PrintJobReportRequest
{
    public int PrintJobId { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
}

// Bentuk payload JSON print_jobs untuk job_type BUNDLE_LABEL (lihat sql/sp_Bundle_Manage.sql,
// dirakit lewat FOR JSON PATH dengan nama kolom snake_case -- cocokkan lewat JsonPropertyName).
public class BundleLabelPayload
{
    [JsonPropertyName("serial")]
    public string Serial { get; set; } = string.Empty;

    [JsonPropertyName("bundle_no")]
    public int BundleNo { get; set; }

    [JsonPropertyName("qr_content")]
    public string QrContent { get; set; } = string.Empty;

    [JsonPropertyName("project_name")]
    public string ProjectName { get; set; } = string.Empty;

    [JsonPropertyName("no_po")]
    public string? NoPo { get; set; }

    [JsonPropertyName("material_name")]
    public string? MaterialName { get; set; }

    [JsonPropertyName("article_name")]
    public string ArticleName { get; set; } = string.Empty;

    [JsonPropertyName("style")]
    public string? Style { get; set; }

    [JsonPropertyName("color")]
    public string? Color { get; set; }

    [JsonPropertyName("size_pack_name")]
    public string? SizePackName { get; set; }

    [JsonPropertyName("size_name")]
    public string SizeName { get; set; } = string.Empty;

    [JsonPropertyName("qty")]
    public int Qty { get; set; }

    [JsonPropertyName("resource_name")]
    public string? ResourceName { get; set; }

    [JsonPropertyName("resource_person_name")]
    public string? ResourcePersonName { get; set; }

    [JsonPropertyName("started_at")]
    public DateTime StartedAt { get; set; }
}
