-- Migrasi untuk DB yang sudah ada: tabel stations + index.
-- Idempotent, aman dijalankan berulang.

IF OBJECT_ID('stations', 'U') IS NULL
BEGIN
    CREATE TABLE stations(
     station_id int primary key identity(1,1),
     station_code varchar(30) not null,
     station_name varchar(150) not null,
     division_id int not null
       constraint FK_stations_divisions foreign key references divisions(division_id),
     station_token varchar(64) not null,        -- GUID tanpa strip, digenerate server
     is_active bit not null default 1,
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_stations_code' AND object_id = OBJECT_ID('stations'))
    CREATE UNIQUE INDEX UX_stations_code ON stations(station_code) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_stations_token' AND object_id = OBJECT_ID('stations'))
    CREATE UNIQUE INDEX UX_stations_token ON stations(station_token) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stations_division' AND object_id = OBJECT_ID('stations'))
    CREATE INDEX IX_stations_division ON stations(division_id) WHERE deleted_at IS NULL;
GO
