-- =============================================================
-- Seed master order, area rawatan, dan satuan PDH TNI AD 2026 (Prompt 61)
-- Nama area & satuan diambil PERSIS dari data mentah Google Form (dipakai
-- untuk mencocokkan saat import -- jangan diubah ejaannya).
-- satuan_code = USULAN, silakan ubah SEBELUM dijalankan. Setelah personel
-- di-import, kode ini ikut tercetak di kartu (DTJ-001) dan box (BDG-DTJ-01),
-- jadi jangan diubah lagi setelahnya.
-- Idempotent.
-- =============================================================
SET NOCOUNT ON;
DECLARE @SeedUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
IF @SeedUserId IS NULL BEGIN RAISERROR('Tidak ada user Admin untuk created_by seed.',16,1); RETURN; END

IF NOT EXISTS (SELECT 1 FROM tni.orders WHERE order_code = 'PDH_OPMAT_2026' AND deleted_at IS NULL)
    INSERT INTO tni.orders (order_code, order_name, instansi, tahun, target_qty, is_active, created_by)
    VALUES ('PDH_OPMAT_2026', 'PDH Opmat 2026', 'Kodam III/Siliwangi', 2026, 8000, 1, @SeedUserId);

DECLARE @OrderId INT = (SELECT order_id FROM tni.orders WHERE order_code = 'PDH_OPMAT_2026' AND deleted_at IS NULL);

IF NOT EXISTS (SELECT 1 FROM tni.area_rawatan WHERE order_id = @OrderId AND area_code = 'BDG' AND deleted_at IS NULL)
    INSERT INTO tni.area_rawatan (order_id, area_code, area_name, kota, created_by) VALUES (@OrderId, 'BDG', 'Tepbek III/1.A Bandung', 'Bandung', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.area_rawatan WHERE order_id = @OrderId AND area_code = 'CMH' AND deleted_at IS NULL)
    INSERT INTO tni.area_rawatan (order_id, area_code, area_name, kota, created_by) VALUES (@OrderId, 'CMH', 'Tepbek III/2.A Cimahi', 'Cimahi', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.area_rawatan WHERE order_id = @OrderId AND area_code = 'BGR' AND deleted_at IS NULL)
    INSERT INTO tni.area_rawatan (order_id, area_code, area_name, kota, created_by) VALUES (@OrderId, 'BGR', 'Denbekang III/1.B Bogor', 'Bogor', @SeedUserId);

-- BGR: 2 satuan
DECLARE @Area_BGR INT = (SELECT area_id FROM tni.area_rawatan WHERE order_id = @OrderId AND area_code = 'BGR' AND deleted_at IS NULL);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BGR AND satuan_name = 'Pusdikintel Pusintelad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BGR, 'DINT', 'Pusdikintel Pusintelad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BGR AND satuan_name = 'Pusdikzi Pusziad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BGR, 'DIZI', 'Pusdikzi Pusziad', @SeedUserId);

-- BDG: 21 satuan
DECLARE @Area_BDG INT = (SELECT area_id FROM tni.area_rawatan WHERE order_id = @OrderId AND area_code = 'BDG' AND deleted_at IS NULL);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'BengpusKomlek' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'BKML', 'BengpusKomlek', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Bengpuspal' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'BPAL', 'Bengpuspal', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Disjarahad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'JRH', 'Disjarahad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Dislitbangad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'LBG', 'Dislitbangad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Dispsiad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'PSI', 'Dispsiad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Ditajenad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'DTJ', 'Ditajenad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Ditkuad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'DKU', 'Ditkuad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Gupus II/ Puskesad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'GKES', 'Gupus II/ Puskesad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Gupusmu' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'GMU', 'Gupusmu', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Kodiklatad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'KDL', 'Kodiklatad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Kupus II/Ditkuad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'KKU', 'Kupus II/Ditkuad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Lafiad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'LAF', 'Lafiad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Pusdikajen Ditajenad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'DAJN', 'Pusdikajen Ditajenad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Pusdikif Pussenif' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'DIF', 'Pusdikif Pussenif', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Pusdikkowad Kodiklatad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'DKWD', 'Pusdikkowad Kodiklatad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Pusdikku Ditkuad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'DIKU', 'Pusdikku Ditkuad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Pusdikkum Ditkumad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'DKUM', 'Pusdikkum Ditkumad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Pussenif' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'PIF', 'Pussenif', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Pussenkav' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'PKAV', 'Pussenkav', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Pussimpur' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'SMP', 'Pussimpur', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_BDG AND satuan_name = 'Seskoad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_BDG, 'SSK', 'Seskoad', @SeedUserId);

-- CMH: 15 satuan
DECLARE @Area_CMH INT = (SELECT area_id FROM tni.area_rawatan WHERE order_id = @OrderId AND area_code = 'CMH' AND deleted_at IS NULL);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Bengpus Armed' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'BARM', 'Bengpus Armed', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Bengpuskav' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'BKAV', 'Bengpuskav', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Disjasad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'JAS', 'Disjasad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikarmed Pussenarmed' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DARM', 'Pusdikarmed Pussenarmed', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikbekang Pusbekangad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DBKG', 'Pusdikbekang Pusbekangad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikjas Disjasad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DJAS', 'Pusdikjas Disjasad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikkav Pussenkav' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DKAV', 'Pusdikkav Pussenkav', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikkomlek Puskomlekad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DKML', 'Pusdikkomlek Puskomlekad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikpal Puspalad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DPAL', 'Pusdikpal Puspalad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikpengmilum Kodiklatad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DPMU', 'Pusdikpengmilum Kodiklatad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikpom Puspomad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DPOM', 'Pusdikpom Puspomad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdikter Pusterad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DTER', 'Pusdikter Pusterad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusdiktop Ditopad' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'DTOP', 'Pusdiktop Ditopad', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pusenarhanud' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'PARH', 'Pusenarhanud', @SeedUserId);
IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE area_id = @Area_CMH AND satuan_name = 'Pussenarmed' AND deleted_at IS NULL)
    INSERT INTO tni.satuan (area_id, satuan_code, satuan_name, created_by) VALUES (@Area_CMH, 'PARM', 'Pussenarmed', @SeedUserId);

-- Verifikasi (subquery tidak boleh langsung di dalam PRINT/CONCAT -- tampung dulu ke variabel).
DECLARE @CntArea INT = (SELECT COUNT(*) FROM tni.area_rawatan WHERE order_id = @OrderId AND deleted_at IS NULL);
DECLARE @CntSatuan INT = (SELECT COUNT(*) FROM tni.satuan s JOIN tni.area_rawatan a ON a.area_id = s.area_id WHERE a.order_id = @OrderId AND s.deleted_at IS NULL);
DECLARE @CntKodeUnik INT = (SELECT COUNT(DISTINCT s.satuan_code) FROM tni.satuan s JOIN tni.area_rawatan a ON a.area_id = s.area_id WHERE a.order_id = @OrderId AND s.deleted_at IS NULL);
PRINT CONCAT('area: ', @CntArea, ' (harus 3), satuan: ', @CntSatuan, ' (harus 38), satuan_code unik: ', @CntKodeUnik, ' (harus sama dengan jumlah satuan)');
IF @CntKodeUnik <> @CntSatuan RAISERROR('satuan_code DOBEL dalam satu order -- wajib unik (Prompt 60).',16,1);
