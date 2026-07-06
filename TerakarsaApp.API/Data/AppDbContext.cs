using Microsoft.EntityFrameworkCore;

namespace TerakarsaApp.API.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }
}