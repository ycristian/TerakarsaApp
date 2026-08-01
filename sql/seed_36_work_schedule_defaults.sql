-- Prompt 36 -- Seed awal work_schedule_defaults & work_break_defaults. Idempotent: hanya
-- mengisi baris yang belum ada, tidak menimpa data yang sudah dikustomisasi lewat UI.
-- Jalankan SETELAH alter_36_dashboard_target.sql.

DECLARE @AdminUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);

-- Senin(1)-Sabtu(6) 08:00-20:00 kerja, Minggu(7) 08:00-20:00 libur default.
INSERT INTO work_schedule_defaults (division_id, day_of_week, is_working_day, start_time, end_time, created_at, created_by)
SELECT d.division_id, dow.day_of_week,
       CASE WHEN dow.day_of_week = 7 THEN 0 ELSE 1 END,
       '08:00', '20:00',
       SYSDATETIME(), @AdminUserId
FROM divisions d
CROSS JOIN (VALUES (1), (2), (3), (4), (5), (6), (7)) dow(day_of_week)
WHERE d.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM work_schedule_defaults wsd
      WHERE wsd.division_id = d.division_id
        AND wsd.day_of_week = dow.day_of_week
        AND wsd.deleted_at IS NULL
  );
GO

-- Dua istirahat default, berlaku semua hari.
IF NOT EXISTS (SELECT 1 FROM work_break_defaults WHERE break_name = 'Istirahat Siang' AND deleted_at IS NULL)
    INSERT INTO work_break_defaults (break_name, day_of_week, start_time, end_time, sort_order, created_at, created_by)
    SELECT 'Istirahat Siang', NULL, '12:00', '13:00', 10, SYSDATETIME(), (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
GO

IF NOT EXISTS (SELECT 1 FROM work_break_defaults WHERE break_name = 'Istirahat Sore' AND deleted_at IS NULL)
    INSERT INTO work_break_defaults (break_name, day_of_week, start_time, end_time, sort_order, created_at, created_by)
    SELECT 'Istirahat Sore', NULL, '17:00', '18:00', 20, SYSDATETIME(), (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
GO
