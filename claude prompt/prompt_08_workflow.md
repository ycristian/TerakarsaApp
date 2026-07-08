# Prompt Claude Code — Poin 8: Workflow Template & Workflow Artikel

Dua bagian. Kerjakan Bagian A dulu sampai jalan, baru Bagian B.
Tabel sudah ada: `workflow_templates`, `workflow_template_steps`, `article_workflows`. Jangan ubah struktur tabel.

## Bagian A — Master Workflow Template (module baru)

Master-detail satu layar, pola sama persis dengan Size Pack: header + grid steps.

### Form
| Field | Aturan |
|---|---|
| workflow_code | wajib, max 30, unik (di antara data hidup) |
| workflow_name | wajib, max 150 |
| Grid steps | minimal 1 baris. Per baris: step_name (wajib, max 150), division_id (wajib, dropdown divisi hidup), sort_order (angka, urutan proses). Bisa tambah/hapus baris dan ubah urutan. |

### Stored Procedure
- `sp_WorkflowTemplate_Manage` (@Action CREATE/UPDATE/DELETE):
  - CREATE/UPDATE terima steps sebagai JSON (OPENJSON), header + steps dalam satu transaksi
  - UPDATE: baris yang dihapus user → soft delete; baris baru → insert; baris lama → update
  - DELETE = soft delete header + semua steps
- SP read terpisah:
  - `sp_WorkflowTemplate_List` — paged, search, sorting, kolom jumlah steps
  - `sp_WorkflowTemplate_GetById` — 2 result set: header + steps hidup urut sort_order (JOIN division_name)

### Module
Code: `MASTER_WORKFLOW`, grup "Master Data", assign ke admin.

## Bagian B — Workflow Artikel (section baru di halaman edit Artikel)

Tanpa module baru — privilege module PROJECT. Section "Workflow" di halaman edit artikel, di bawah bagian foto.

**Konsep penting**: template hanyalah **arahan awal** (default). Setelah steps di-copy ke artikel, workflow sepenuhnya milik artikel — bebas diedit manual, tidak ada kaitan lagi dengan template selain info asal.

### Perilaku
1. **Artikel belum punya workflow**: tampilkan dropdown template (hidup) + tombol "Terapkan Template".
   Klik → steps template di-copy ke `article_workflows` (step_name, division_id, sort_order, dan `workflow_template_id` diisi sebagai info asal) dalam satu transaksi.
2. **Setelah diterapkan**: dropdown hilang, tampilkan nama template asal sebagai info read-only. **Template tidak boleh diganti** — tidak ada tombol ganti/reset.
3. **Steps bisa diedit bebas** setelah copy: tambah baris baru (workflow_template_id = NULL untuk step manual), ubah step_name/divisi/sort_order, hapus baris (soft delete). Perubahan template TIDAK mempengaruhi artikel yang sudah punya workflow.
4. Grid steps: nomor urut, step_name, dropdown divisi, sort_order, tombol hapus per baris. Tombol "Simpan Workflow" menyimpan semua perubahan sekaligus.

### Stored Procedure
- `sp_ArticleWorkflow_Manage` dengan @Action:
  - `APPLY` (@ArticleId, @WorkflowTemplateId): copy steps dari template. **Tolak dengan error jelas jika artikel sudah punya steps hidup.**
  - `SAVE` (@ArticleId, @Steps JSON): insert/update/soft delete steps dalam satu transaksi.
  - Guard pada soft delete step: tolak jika step sudah punya baris hidup di `article_workflow_logs` (tabel sudah ada meskipun belum dipakai — mencegah bug di Phase E).
- SP read: `sp_ArticleWorkflow_ListByArticle` (@ArticleId) — steps hidup urut sort_order, JOIN division_name, plus info nama template asal jika ada.

## Aturan tetap berlaku
Soft delete, filter deleted_at IS NULL, UserId dari JWT, konfirmasi delete, UI bahasa Indonesia.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.
