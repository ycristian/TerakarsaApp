-- Prompt 38 -- Dashboard Target Harian: token kiosk untuk layar TV. Idempotent: aman
-- dijalankan berulang. Berbeda dari stations -- tabel ini TIDAK terikat divisi, dan boleh
-- ada banyak token aktif bersamaan (satu per TV).

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'dashboard_tokens')
BEGIN
    CREATE TABLE dashboard_tokens(
     dashboard_token_id int primary key identity(1,1),
     token_name varchar(150) not null,          -- mis. 'TV Line Jahit 1'
     dashboard_token varchar(64) not null,      -- GUID tanpa strip, digenerate server
     is_active bit not null default 1,
     refresh_interval_minutes int not null default 30,  -- harus habis membagi 60

     last_seen_at datetime2 null,               -- diperbarui saat token dipakai
     created_at datetime2 not null default sysdatetime(),
     created_by int not null,
     updated_at datetime2 null,
     updated_by int null,
     deleted_at datetime2 null,
     deleted_by int null,
     constraint CK_dashboard_tokens_refresh_interval check (refresh_interval_minutes in (5, 10, 15, 20, 30, 60))
    );

    CREATE UNIQUE INDEX UX_dashboard_tokens_token ON dashboard_tokens(dashboard_token) WHERE deleted_at IS NULL;
    CREATE UNIQUE INDEX UX_dashboard_tokens_name ON dashboard_tokens(token_name) WHERE deleted_at IS NULL;
END
GO
