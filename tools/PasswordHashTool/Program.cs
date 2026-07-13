if (args.Length != 1)
{
    Console.Error.WriteLine("Pakai: dotnet run --project tools/PasswordHashTool -- <password>");
    return 1;
}

Console.WriteLine(PasswordHasher.Hash(args[0]));
return 0;

// Duplikasi dari TerakarsaApp.API/Services/PasswordHasher.cs (Prompt 21) supaya tool ini
// tetap standalone tanpa mereferensikan project API. Kalau format hash di sana berubah,
// samakan juga di sini.
static class PasswordHasher
{
    private const string Prefix = "PBKDF2";
    private const int Iterations = 210000;
    private const int SaltSize = 16;
    private const int HashSize = 32;

    public static string Hash(string password)
    {
        var salt = System.Security.Cryptography.RandomNumberGenerator.GetBytes(SaltSize);
        var hash = System.Security.Cryptography.Rfc2898DeriveBytes.Pbkdf2(
            password, salt, Iterations, System.Security.Cryptography.HashAlgorithmName.SHA256, HashSize);

        return $"{Prefix}${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }
}
