using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using TerakarsaApp.Client;
using TerakarsaApp.Client.Auth;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddScoped<CustomAuthStateProvider>();
builder.Services.AddScoped<Microsoft.AspNetCore.Components.Authorization.AuthenticationStateProvider>(
    sp => sp.GetRequiredService<CustomAuthStateProvider>());
builder.Services.AddAuthorizationCore();

builder.Services.AddScoped<AuthorizedHandler>();

builder.Services.AddHttpClient("AuthAPI", client =>
{
    client.BaseAddress = new Uri("http://localhost:5281/");
});

builder.Services.AddHttpClient("API", client =>
{
    client.BaseAddress = new Uri("http://localhost:5281/");
})
.AddHttpMessageHandler<AuthorizedHandler>();

builder.Services.AddScoped(sp =>
    sp.GetRequiredService<IHttpClientFactory>().CreateClient("API"));

builder.Services.AddScoped<TerakarsaApp.Client.Auth.StationTokenHandler>();

builder.Services.AddHttpClient<TerakarsaApp.Client.Services.StationDeviceApiService>(client =>
{
    client.BaseAddress = new Uri("http://localhost:5281/");
})
.AddHttpMessageHandler<TerakarsaApp.Client.Auth.StationTokenHandler>();

builder.Services.AddScoped<AuthApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ProductApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.UserApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ModuleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.DivisionApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.PositionApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ResourceTypeApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ResourceApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.BuyerApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.EmployeeApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ProjectApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ProjectAttachmentApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.SizePackApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ArticleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ArticlePhotoApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.WorkflowTemplateApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ArticleWorkflowApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.StationApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.WorkflowLogApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.BundleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.PublicBundleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.WorkflowInputApiService>();

await builder.Build().RunAsync();