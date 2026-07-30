-- Bulk insert karyawan penjahit (division SEW + QC, position Penjahit)
-- lewat SIS_Employee_Manage supaya validasi duplikat employee_code tetap ditegakkan.
-- Jalankan manual sekali; SP akan RAISERROR kalau employee_code sudah ada.

DECLARE @UserId INT = 4; -- ivander

EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=3,  @PositionId=8, @EmployeeCode='SW-001', @EmployeeName=N'Iki',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=3,  @PositionId=8, @EmployeeCode='SW-002', @EmployeeName=N'Erwin',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=3,  @PositionId=8, @EmployeeCode='SW-003', @EmployeeName=N'Asep',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=3,  @PositionId=8, @EmployeeCode='SW-004', @EmployeeName=N'Njah',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=3,  @PositionId=8, @EmployeeCode='SW-005', @EmployeeName=N'Popot',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=3,  @PositionId=8, @EmployeeCode='SW-006', @EmployeeName=N'Alan',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=3,  @PositionId=8, @EmployeeCode='SW-007', @EmployeeName=N'Heru',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=7,  @PositionId=8, @EmployeeCode='SW-008', @EmployeeName=N'Agus',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=7,  @PositionId=8, @EmployeeCode='SW-009', @EmployeeName=N'Wiwin',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=7,  @PositionId=8, @EmployeeCode='SW-010', @EmployeeName=N'Dasep',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=7,  @PositionId=8, @EmployeeCode='SW-011', @EmployeeName=N'Amih/Apih',  @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=7,  @PositionId=8, @EmployeeCode='SW-012', @EmployeeName=N'Ade',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=7,  @PositionId=8, @EmployeeCode='SW-013', @EmployeeName=N'Sigit',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=7,  @PositionId=8, @EmployeeCode='SW-014', @EmployeeName=N'Ewok',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=7,  @PositionId=8, @EmployeeCode='SW-015', @EmployeeName=N'Uus',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-016', @EmployeeName=N'Nur',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-017', @EmployeeName=N'Yogi',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-018', @EmployeeName=N'Adi',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-019', @EmployeeName=N'Panji',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-020', @EmployeeName=N'Ebe',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-021', @EmployeeName=N'Ari',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-022', @EmployeeName=N'Yana',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-023', @EmployeeName=N'Aji',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-024', @EmployeeName=N'Iki',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=10, @PositionId=8, @EmployeeCode='SW-025', @EmployeeName=N'Abuy',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-026', @EmployeeName=N'Nia',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-027', @EmployeeName=N'Asep',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-028', @EmployeeName=N'Bram',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-029', @EmployeeName=N'Ida',        @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-030', @EmployeeName=N'Dewi',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-031', @EmployeeName=N'Zaenal',     @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-032', @EmployeeName=N'Lilis',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-033', @EmployeeName=N'Imas',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-034', @EmployeeName=N'Kohar',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-035', @EmployeeName=N'Diki',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=11, @PositionId=8, @EmployeeCode='SW-036', @EmployeeName=N'Ijal',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-037', @EmployeeName=N'Risma',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-038', @EmployeeName=N'Yayat',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-039', @EmployeeName=N'Wawan',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-040', @EmployeeName=N'Agus',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-041', @EmployeeName=N'Awan',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-042', @EmployeeName=N'Fadil',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-043', @EmployeeName=N'Ujang',      @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-044', @EmployeeName=N'Diki',       @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-045', @EmployeeName=N'Adiyana',    @UserId=@UserId;
EXEC SIS_Employee_Manage @Action='CREATE', @DivisionId=2, @ResourceId=12, @PositionId=8, @EmployeeCode='SW-046', @EmployeeName=N'Dani',       @UserId=@UserId;
GO
