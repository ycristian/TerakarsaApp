using System.IO;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging;
using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.GateApp.Services;

// Satu baris antrian tap yang belum terkirim.
public class QueuedTap
{
    public Guid TapUid { get; set; }
    public string CardUid { get; set; } = string.Empty;
    public DateTime TappedAt { get; set; }
    public string? ConfirmAction { get; set; }
}

// Prompt 70: gate.db di folder exe.
//   cards & employees -> CACHE MURNI, ditimpa penuh tiap sync berhasil. Boleh dihapus kapan
//     saja; tidak pernah jadi sumber kebenaran (nama di layar offline hanya untuk mata satpam,
//     penentuan masuk/pulang tetap milik server).
//   tap_queue        -> satu-satunya data yang TIDAK boleh hilang. Dikirim urut tapped_at.
//
// Kalau file-nya korup, konstruktor menghapus dan membuat ulang: kehilangan cache tidak apa-apa,
// dan aplikasi harus tetap hidup supaya tap berikutnya masih tercatat.
public class GateLocalDb
{
    private readonly string _path;
    private readonly ILogger<GateLocalDb> _logger;
    private readonly object _lock = new();

    public GateLocalDb(ILogger<GateLocalDb> logger)
    {
        _logger = logger;
        _path = Path.Combine(AppContext.BaseDirectory, "gate.db");

        try
        {
            EnsureSchema();
        }
        catch (SqliteException ex)
        {
            _logger.LogWarning(ex, "gate.db tidak bisa dibuka, file dibuat ulang.");
            try { File.Delete(_path); } catch (IOException) { /* dipakai proses lain: biarkan EnsureSchema gagal di bawah */ }
            EnsureSchema();
        }
    }

    private string ConnectionString => $"Data Source={_path}";

    private void EnsureSchema()
    {
        using var conn = new SqliteConnection(ConnectionString);
        conn.Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS cards (
                card_uid TEXT PRIMARY KEY,
                card_type TEXT NOT NULL,
                employee_id INTEGER NOT NULL,
                employee_name TEXT NOT NULL,
                employee_code TEXT NULL,
                position_name TEXT NOT NULL,
                is_gate_operator INTEGER NOT NULL,
                division_id INTEGER NOT NULL,
                division_name TEXT NOT NULL,
                resource_name TEXT NULL,
                color_hex TEXT NULL
            );
            CREATE TABLE IF NOT EXISTS employees (
                employee_id INTEGER PRIMARY KEY,
                employee_name TEXT NOT NULL,
                employee_code TEXT NULL,
                phone TEXT NULL,
                division_id INTEGER NOT NULL,
                division_name TEXT NOT NULL,
                position_name TEXT NOT NULL,
                resource_id INTEGER NULL,
                resource_name TEXT NULL,
                color_hex TEXT NULL,
                has_active_card INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS tap_queue (
                tap_uid TEXT PRIMARY KEY,
                card_uid TEXT NOT NULL,
                tapped_at TEXT NOT NULL,
                confirm_action TEXT NULL,
                sent INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS ix_tap_queue_pending ON tap_queue(sent, tapped_at);
            """;
        cmd.ExecuteNonQuery();
    }

    // Ditimpa PENUH: baris yang hilang di server (kartu dinonaktifkan) harus ikut hilang dari
    // cache, kalau tidak kartu nonaktif masih tampil bernama di layar offline.
    public void ReplaceCache(GateCardSyncResult sync)
    {
        lock (_lock)
        {
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var tx = conn.BeginTransaction();

            Exec(conn, tx, "DELETE FROM cards");
            Exec(conn, tx, "DELETE FROM employees");

            foreach (var card in sync.Cards)
            {
                using var cmd = conn.CreateCommand();
                cmd.Transaction = tx;
                cmd.CommandText = """
                    INSERT INTO cards (card_uid, card_type, employee_id, employee_name, employee_code,
                                       position_name, is_gate_operator, division_id, division_name,
                                       resource_name, color_hex)
                    VALUES ($uid, $type, $eid, $name, $code, $pos, $op, $did, $dname, $res, $color)
                    """;
                cmd.Parameters.AddWithValue("$uid", card.CardUid);
                cmd.Parameters.AddWithValue("$type", card.CardType);
                cmd.Parameters.AddWithValue("$eid", card.EmployeeId);
                cmd.Parameters.AddWithValue("$name", card.EmployeeName);
                cmd.Parameters.AddWithValue("$code", (object?)card.EmployeeCode ?? DBNull.Value);
                cmd.Parameters.AddWithValue("$pos", card.PositionName);
                cmd.Parameters.AddWithValue("$op", card.IsGateOperator ? 1 : 0);
                cmd.Parameters.AddWithValue("$did", card.DivisionId);
                cmd.Parameters.AddWithValue("$dname", card.DivisionName);
                cmd.Parameters.AddWithValue("$res", (object?)card.ResourceName ?? DBNull.Value);
                cmd.Parameters.AddWithValue("$color", (object?)card.ColorHex ?? DBNull.Value);
                cmd.ExecuteNonQuery();
            }

            foreach (var emp in sync.Employees)
            {
                using var cmd = conn.CreateCommand();
                cmd.Transaction = tx;
                cmd.CommandText = """
                    INSERT INTO employees (employee_id, employee_name, employee_code, phone, division_id,
                                           division_name, position_name, resource_id, resource_name,
                                           color_hex, has_active_card)
                    VALUES ($eid, $name, $code, $phone, $did, $dname, $pos, $rid, $res, $color, $hascard)
                    """;
                cmd.Parameters.AddWithValue("$eid", emp.EmployeeId);
                cmd.Parameters.AddWithValue("$name", emp.EmployeeName);
                cmd.Parameters.AddWithValue("$code", (object?)emp.EmployeeCode ?? DBNull.Value);
                cmd.Parameters.AddWithValue("$phone", (object?)emp.Phone ?? DBNull.Value);
                cmd.Parameters.AddWithValue("$did", emp.DivisionId);
                cmd.Parameters.AddWithValue("$dname", emp.DivisionName);
                cmd.Parameters.AddWithValue("$pos", emp.PositionName);
                cmd.Parameters.AddWithValue("$rid", (object?)emp.ResourceId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("$res", (object?)emp.ResourceName ?? DBNull.Value);
                cmd.Parameters.AddWithValue("$color", (object?)emp.ColorHex ?? DBNull.Value);
                cmd.Parameters.AddWithValue("$hascard", emp.HasActiveCard ? 1 : 0);
                cmd.ExecuteNonQuery();
            }

            tx.Commit();
        }
    }

    public List<GateCardDto> GetCards()
    {
        lock (_lock)
        {
            var list = new List<GateCardDto>();
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT card_uid, card_type, employee_id, employee_name, employee_code, position_name, is_gate_operator, division_id, division_name, resource_name, color_hex FROM cards";
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                list.Add(new GateCardDto
                {
                    CardUid = reader.GetString(0),
                    CardType = reader.GetString(1),
                    EmployeeId = reader.GetInt32(2),
                    EmployeeName = reader.GetString(3),
                    EmployeeCode = reader.IsDBNull(4) ? null : reader.GetString(4),
                    PositionName = reader.GetString(5),
                    IsGateOperator = reader.GetInt32(6) == 1,
                    DivisionId = reader.GetInt32(7),
                    DivisionName = reader.GetString(8),
                    ResourceName = reader.IsDBNull(9) ? null : reader.GetString(9),
                    ColorHex = reader.IsDBNull(10) ? null : reader.GetString(10),
                });
            }
            return list;
        }
    }

    public List<GateEmployeeDto> GetEmployees()
    {
        lock (_lock)
        {
            var list = new List<GateEmployeeDto>();
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT employee_id, employee_name, employee_code, phone, division_id, division_name, position_name, resource_id, resource_name, color_hex, has_active_card FROM employees ORDER BY division_name, resource_name, employee_name";
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                list.Add(new GateEmployeeDto
                {
                    EmployeeId = reader.GetInt32(0),
                    EmployeeName = reader.GetString(1),
                    EmployeeCode = reader.IsDBNull(2) ? null : reader.GetString(2),
                    Phone = reader.IsDBNull(3) ? null : reader.GetString(3),
                    DivisionId = reader.GetInt32(4),
                    DivisionName = reader.GetString(5),
                    PositionName = reader.GetString(6),
                    ResourceId = reader.IsDBNull(7) ? null : reader.GetInt32(7),
                    ResourceName = reader.IsDBNull(8) ? null : reader.GetString(8),
                    ColorHex = reader.IsDBNull(9) ? null : reader.GetString(9),
                    HasActiveCard = reader.GetInt32(10) == 1,
                });
            }
            return list;
        }
    }

    // tap_uid dibuat SEBELUM pengiriman dan dipakai apa adanya saat dikirim ulang -- itulah
    // kunci idempoten di sisi server (gate_taps.tap_uid unique).
    public void EnqueueTap(Guid tapUid, string cardUid, DateTime tappedAt, string? confirmAction)
    {
        lock (_lock)
        {
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                INSERT OR REPLACE INTO tap_queue (tap_uid, card_uid, tapped_at, confirm_action, sent)
                VALUES ($uid, $card, $at, $confirm, 0)
                """;
            cmd.Parameters.AddWithValue("$uid", tapUid.ToString());
            cmd.Parameters.AddWithValue("$card", cardUid);
            cmd.Parameters.AddWithValue("$at", tappedAt.ToString("O"));
            cmd.Parameters.AddWithValue("$confirm", (object?)confirmAction ?? DBNull.Value);
            cmd.ExecuteNonQuery();
        }
    }

    // Urut tapped_at: sesi dibangun dari urutan waktu tap asli, jadi urutan kirim tidak boleh
    // menentukan hasil.
    public List<QueuedTap> GetPendingTaps(int max)
    {
        lock (_lock)
        {
            var list = new List<QueuedTap>();
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT tap_uid, card_uid, tapped_at, confirm_action FROM tap_queue WHERE sent = 0 ORDER BY tapped_at ASC LIMIT $max";
            cmd.Parameters.AddWithValue("$max", max);
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                list.Add(new QueuedTap
                {
                    TapUid = Guid.Parse(reader.GetString(0)),
                    CardUid = reader.GetString(1),
                    TappedAt = DateTime.Parse(reader.GetString(2), null, System.Globalization.DateTimeStyles.RoundtripKind),
                    ConfirmAction = reader.IsDBNull(3) ? null : reader.GetString(3),
                });
            }
            return list;
        }
    }

    public int GetPendingCount()
    {
        lock (_lock)
        {
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM tap_queue WHERE sent = 0";
            return Convert.ToInt32(cmd.ExecuteScalar() ?? 0);
        }
    }

    public void MarkSent(Guid tapUid)
    {
        lock (_lock)
        {
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "UPDATE tap_queue SET sent = 1 WHERE tap_uid = $uid";
            cmd.Parameters.AddWithValue("$uid", tapUid.ToString());
            cmd.ExecuteNonQuery();
        }
    }

    // Cooldown dicek LOKAL dulu supaya tap dobel tidak membebani API. Dibaca dari antrian
    // (termasuk baris yang sudah terkirim) -- server tetap mengecek ulang.
    public DateTime? GetLastTapAt(string cardUid)
    {
        lock (_lock)
        {
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT MAX(tapped_at) FROM tap_queue WHERE card_uid = $card";
            cmd.Parameters.AddWithValue("$card", cardUid);
            var value = cmd.ExecuteScalar();
            if (value is null || value is DBNull) return null;
            return DateTime.Parse((string)value, null, System.Globalization.DateTimeStyles.RoundtripKind);
        }
    }

    // Baris yang sudah terkirim dibersihkan setelah 7 hari -- cukup lama untuk menelusuri
    // masalah, cukup pendek supaya file tidak tumbuh selamanya.
    public void PurgeSentOlderThan(TimeSpan age)
    {
        lock (_lock)
        {
            using var conn = new SqliteConnection(ConnectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "DELETE FROM tap_queue WHERE sent = 1 AND tapped_at < $cutoff";
            cmd.Parameters.AddWithValue("$cutoff", DateTime.Now.Subtract(age).ToString("O"));
            cmd.ExecuteNonQuery();
        }
    }

    private static void Exec(SqliteConnection conn, SqliteTransaction tx, string sql)
    {
        using var cmd = conn.CreateCommand();
        cmd.Transaction = tx;
        cmd.CommandText = sql;
        cmd.ExecuteNonQuery();
    }
}
