-- Prompt 58 (lanjutan): jabatan dibatasi per divisi -- mis. divisi "Sew + QC" hanya menawarkan
-- Penjahit, Helper, dan QC. Idempotent, dijalankan MANUAL.
--
-- MANY-TO-MANY, bukan kolom division_id di positions: satu jabatan (mis. "Helper") dipakai
-- beberapa divisi, dan positions yang sudah ada sekarang dipakai lintas divisi oleh employees.
--
-- ATURAN FALLBACK (ditegakkan di SIS_Position_GetByDivision): divisi yang BELUM punya satu pun
-- baris di sini dianggap "belum diatur" dan tetap menawarkan SEMUA jabatan. Jadi script ini
-- aman dijalankan tanpa seed -- perilaku lama tidak berubah sampai admin mengisinya di
-- Master Divisi.

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'division_positions')
BEGIN
    CREATE TABLE division_positions(
     division_position_id int primary key identity(1,1),
     division_id int not null
       constraint FK_divpos_divisions foreign key references divisions(division_id),
     position_id int not null
       constraint FK_divpos_positions foreign key references positions(position_id),
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null
    );

    CREATE UNIQUE INDEX UX_divpos_division_position ON division_positions(division_id, position_id)
        WHERE deleted_at IS NULL;
END
GO
