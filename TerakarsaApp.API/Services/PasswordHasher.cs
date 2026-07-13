using System.Security.Cryptography;

namespace TerakarsaApp.API.Services;

// Format simpanan: PBKDF2$<iterations>$<saltBase64>$<hashBase64>
// Iterasi disimpan di string supaya bisa dinaikkan nanti tanpa merusak hash lama.
public static class PasswordHasher
{
    private const string Prefix = "PBKDF2";
    private const int Iterations = 210000;
    private const int SaltSize = 16;
    private const int HashSize = 32;

    public static string Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, HashSize);

        return $"{Prefix}${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }

    public static bool Verify(string password, string stored)
    {
        var parts = stored.Split('$');
        if (parts.Length != 4 || parts[0] != Prefix) return false;
        if (!int.TryParse(parts[1], out var iterations)) return false;

        byte[] salt, expectedHash;
        try
        {
            salt = Convert.FromBase64String(parts[2]);
            expectedHash = Convert.FromBase64String(parts[3]);
        }
        catch (FormatException)
        {
            return false;
        }

        var actualHash = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, expectedHash.Length);

        return CryptographicOperations.FixedTimeEquals(actualHash, expectedHash);
    }
}
