namespace TerakarsaApp.Mobile.Pages;

// Prompt 76: warna & pembantu tampilan app.
//
// UI app ini dibuat CODE-ONLY (tanpa XAML) -- isinya hanya 4 layar utilitas
// (login, pilih tujuan, WebView, setting), jadi tidak ada untungnya menambah
// lapisan XAML + source generator. Semua tampilan "asli" TMOS tetap di web.
public static class Gaya
{
    public static readonly Color Aksen = Color.FromArgb("#0f766e");   // teal, sama dengan web
    public static readonly Color Tinta = Color.FromArgb("#1b1f24");
    public static readonly Color Redup = Color.FromArgb("#5b6168");
    public static readonly Color Latar = Color.FromArgb("#f4f5f3");
    public static readonly Color Kartu = Colors.White;
    public static readonly Color Garis = Color.FromArgb("#e3e5e1");
    public static readonly Color Merah = Color.FromArgb("#c0392b");
    public static readonly Color Biru = Color.FromArgb("#1d4ed8");

    public static Label Judul(string teks) => new()
    {
        Text = teks,
        FontSize = 22,
        FontAttributes = FontAttributes.Bold,
        TextColor = Tinta
    };

    public static Label Keterangan(string teks) => new()
    {
        Text = teks,
        FontSize = 13,
        TextColor = Redup
    };

    public static Button Tombol(string teks, bool utama = true) => new()
    {
        Text = teks,
        HeightRequest = 50,
        CornerRadius = 12,
        FontSize = 16,
        FontAttributes = FontAttributes.Bold,
        BackgroundColor = utama ? Aksen : Kartu,
        TextColor = utama ? Colors.White : Tinta,
        BorderColor = utama ? Aksen : Garis,
        BorderWidth = 1
    };

    public static Entry Isian(string placeholder, bool password = false) => new()
    {
        Placeholder = placeholder,
        IsPassword = password,
        HeightRequest = 50,
        BackgroundColor = Kartu,
        TextColor = Tinta,
        FontSize = 16
    };

    // Badge kecil "Lokal" / "Internet".
    public static Border Badge(Label isi, Color warna) => new()
    {
        Content = isi,
        BackgroundColor = warna,
        Stroke = warna,
        StrokeThickness = 0,
        Padding = new Thickness(10, 4),
        HorizontalOptions = LayoutOptions.Start,
        StrokeShape = new Microsoft.Maui.Controls.Shapes.RoundRectangle { CornerRadius = 999 }
    };

    public static Border KartuTujuan(string judul, string keterangan, string route)
    {
        var isi = new VerticalStackLayout
        {
            Spacing = 4,
            Children =
            {
                new Label { Text = judul, FontSize = 18, FontAttributes = FontAttributes.Bold, TextColor = Tinta },
                new Label { Text = keterangan, FontSize = 13, TextColor = Redup },
                new Label { Text = route, FontSize = 11, TextColor = Redup, FontFamily = "monospace" }
            }
        };

        return new Border
        {
            Content = isi,
            BackgroundColor = Kartu,
            Stroke = Garis,
            StrokeThickness = 1,
            Padding = 16,
            StrokeShape = new Microsoft.Maui.Controls.Shapes.RoundRectangle { CornerRadius = 14 }
        };
    }
}
