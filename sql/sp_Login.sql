-- DEPRECATED (Prompt 21): digantikan SIS_User_GetByUsername + verifikasi PBKDF2 di C#.
-- Tidak ada lagi kode C# yang memanggil SIS_Login. Jangan drop SP ini dari database.
--
-- Catatan: SP SIS_Login dibuat langsung di database sebelum folder sql/ dipakai untuk
-- melacak semua objek (mendahului tabel Users lain di sql/create_tables_tmos_final.sql),
-- jadi source aslinya tidak ada di repo ini. File ini hanya menandai status deprecated;
-- objek SIS_Login yang sesungguhnya tetap berada di database apa adanya.

CREATE PROCEDURE SIS_Login  
    @Username   NVARCHAR(100),  
    @Password   NVARCHAR(255)   -- dikirim sudah dalam bentuk hash dari API  
AS  
BEGIN  
    SET NOCOUNT ON;  
  
    SELECT  
        Id,  
        Username,  
        FullName,  
        Role,  
        IsActive  
   
   FROM Users  
    WHERE Username = @Username  
      AND Password = @Password  
      AND IsActive = 1;  
END;  
  
  