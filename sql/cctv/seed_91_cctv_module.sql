/* =============================================================
   Module CCTV (Prompt 91) -- registrasi module CCTV.
   Satu module untuk seluruh halaman /cctv (Live, Playback, Kamera).

   SENGAJA TIDAK di-assign ke user mana pun (juga tidak ke Admin):
   owner mencentang sendiri untuk akunnya di halaman Kelola User.

   Ini satu-satunya tempat seri 91-94 menyentuh schema dbo (tabel Modules).
   Idempotent: aman dijalankan berulang.
   ============================================================= */

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'CCTV')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('CCTV', 'CCTV', 'Sistem', NULL, 'cctv', 'fe fe-video', 870, 1, GETDATE());
GO
